#!/usr/bin/env ruby

# This script propagates raw item events to month-based summations for each
# item, unit, and person.

# Use bundler to keep dependencies local
require 'rubygems'
require 'bundler/setup'

# Run from the right directory (the parent of the tools dir)
Dir.chdir(File.dirname(File.expand_path(File.dirname(__FILE__))))

# Remainder are the requirements for this program
require 'date'
require 'digest'
require 'fileutils'
require 'json'
require 'logger'
require 'pp'
require 'sequel'
require 'set'
require 'time'
require 'yaml'

# Make puts synchronous (e.g. auto-flush)
STDOUT.sync = true

# The main database we're inserting data into
DB = Sequel.connect(YAML.load_file("config/database.yaml"))

# Log for debugging
File.exists?('statsCalc.sql_log') and File.delete('statsCalc.sql_log')
DB.loggers << Logger.new('statsCalc.sql_log')

# Model class for each table
require_relative './models.rb'

BIG_PRIME = 9223372036854775783 # 2**63 - 25 is prime. Kudos https://primes.utm.edu/lists/2small/0bit.html

# Cache some database values
$googleRefID = Referrer.where(domain: "google.com").first.id.to_s

# It's silly and wasteful to propagate every single little referrer up the chain, so we retain
# a certain number and lump the rest as "other".
MAX_REFS = 30

###################################################################################################
# Data classes (much more efficient in both memory and space than hashes)
class ItemSummary
  attr_accessor :unitsDigest, :peopleDigest, :minMonth
end

class RefAccum
  attr_accessor :refs, :other

  def initialize(h)
    @other = 0
    if !h.nil?
      @refs = h.dup
      clamp
    end
  end

  def initialize_copy(b)
    @other = b.other
    @refs = b.refs.dup
  end

  def add(b)
    @refs.merge!(b.refs) { |k,x,y| x+y }
    @other += b.other
    clamp
  end

  def clamp
    # Keep only the top refs
    while @refs.size > MAX_REFS
      min_val = min_key = nil
      @refs.each { |k,v|
        if min_val.nil? || v < min_val
          min_val = v
          min_key = k
        end
      }
      @other += min_val
      @refs.delete(min_key)
    end
  end

  def to_h
    result = @refs.dup
    @other > 0 and result[:other] = @other
    return result
  end
end

class EventAccum
  attr_accessor :hit, :dl, :post, :google, :counts, :ref

  def initialize(h = nil)
    @hit = @dl = @google = @post = 0
    h.nil? and return
    h.each { |k,v|
      if k == 'hit'
        @hit = v
      elsif k == 'dl'
        @dl = v
      elsif k == 'post'
        @post = v
      elsif k == 'ref'
        if h.size == 1 && h.keys[0] == $googleRefID
          @google = h[$googleRefID]
        else
          tmp = h[k].dup
          if tmp[$googleRefID]
            @google = tmp[$googleRefID]
            tmp.delete($googleRefID)
          end
          @ref = RefAccum.new(tmp)
        end
      else
        @counts ||= {}
        @counts[k] = v
      end
    }
  end

  def incPost
    @post += 1
  end

  def add(b)
    # Inline the most common properties for speed and memory efficiency
    @hit    += b.hit
    @dl     += b.dl
    @post   += b.post
    @google += b.google

    # Hash for less common counts
    if @counts.nil?
      b.counts.nil? or @counts = b.counts.clone
    elsif !b.counts.nil?
      @counts.merge!(b.counts) { |k,x,y| x+y }
    end

    # Hash for less common refs
    if @ref.nil?
      b.ref.nil? or @ref = b.ref.clone
    elsif !b.ref.nil?
      @ref.add(b.ref)
    end
  end

  def to_h
    result = {}
    @hit > 0 and result[:hit] = @hit
    @dl > 0 and result[:dl] = @dl
    @post > 0 and result[:post] = @post
    @other.nil? or result.merge!(@other)
    if @google > 0
      result[:ref] = { $googleRefID => @google }
      @ref.nil? or result[:ref].merge!(@ref.to_h)
    elsif !@ref.nil?
      result[:ref] = @ref.to_h
    end
    return result
  end
end

###################################################################################################
def parseDate(dateStr)
  ret = Date.strptime(dateStr, "%Y-%m-%d")
  ret.year > 1000 && ret.year < 4000 or raise("can't parse date #{dateStr}")
  return ret
end

###################################################################################################
# Convert a digest (e.g. MD5, SHA1) to a 63-bit number for memory efficiency
def calcIntDigest(digester)
  return digester.hexdigest.to_i(16) % BIG_PRIME
end

###################################################################################################
# Convert a digest (e.g. MD5, SHA1) to a short base-64 digest, without trailing '='
def calcBase64Digest(digester)
  return digester.base64digest.sub(/=+$/,'')
end

###################################################################################################
$fooRand = Random.new
def createPersonArk
  # FIXME: generate arks when we our shoulder has been granted
  return "foo:#{$fooRand.rand(BIG_PRIME)}"
end

###################################################################################################
# Connect people to authors
def connectAuthors

  # Skip if all authors were already connected
  unconnectedAuthors = ItemAuthor.where(Sequel.lit("attrs->'$.email' is not null and person_id is null"))
  nTodo = unconnectedAuthors.count
  nTodo > 0 or return

  # First, record existing email -> person correlations
  emailToPerson = {}
  Person.where(Sequel.lit("attrs->'$.email' is not null")).each { |person|
    email = JSON.parse(person.attrs)["email"].downcase
    if emailToPerson.key?(email) && emailToPerson[email] != person.id
      puts "Warning: multiple matching people for email #{email.inspect}"
    end
    emailToPerson[email] = person.id
  }

  # Then connect all unconnected authors to people
  nDone = 0
  DB.transaction {
    unconnectedAuthors.each { |auth|
      email = JSON.parse(auth.attrs)["email"].downcase
      person = emailToPerson[email]
      (nDone % 1000) == 0 and puts "Connecting authors: #{nDone} / #{nTodo}"
      if !person
        person = createPersonArk()
        Person.create(id: person, attrs: { email: email }.to_json)
        emailToPerson[email] = person
      end
      ItemAuthor.where(item_id: auth.item_id, ordering: auth.ordering).update(person_id: person)
      nDone += 1
    }
  }
  puts "Connecting authors: #{nDone} / #{nTodo}"
end

###################################################################################################
# Calculate the hash of units for each item
def calcUnitDigests(result)
  prevItem, digester = nil, nil
  UnitItem.select_order_map([:item_id, :unit_id]).each { |item, unit|
    if prevItem != item
      prevItem.nil? or result[prevItem].unitsDigest = calcIntDigest(digester)
      prevItem, digester = item, Digest::MD5.new
    end
    digester << unit
  }
  prevItem.nil? or result[prevItem].unitsDigest = calcIntDigest(digester)
  return result
end

###################################################################################################
# Calculate the hash of units for each item
def calcPeopleDigests(result)
  prevItem, digester = nil, nil
  ItemAuthor.where(Sequel.~(person_id: nil)).select_order_map([:item_id, :person_id]).each { |item, person|
    if prevItem != item
      prevItem.nil? or result[prevItem].peopleDigest = calcIntDigest(digester)
      prevItem, digester = item, Digest::MD5.new
    end
    digester << person
  }
  prevItem.nil? or result[prevItem].peopleDigest = calcIntDigest(digester)
  return result
end

###################################################################################################
# Get minimum effective month for every item
def calcMinMonths(result)
  # Start with the submission date for each item
  Item.where(Sequel.lit("attrs->'$.submission_date' is not null")).select_map([:id, :attrs]).each { |item, attrStr|
    subDate = parseDate(JSON.parse(attrStr)["submission_date"])
    subDate.year >= 1995 or raise("invalid pre-1995 submission date #{subDate.iso8601} for item #{item}")
    result[item].minMonth = subDate.year*100 + subDate.month
  }

  minSym = "min(`date`)".to_sym
  ItemEvent.select_group(:item_id).select_append{min(:date)}.each { |record|
    item = record[:item_id]
    minDate = record[minSym]
    minMonth = minDate.year*100 + minDate.month
    if result[item].minMonth.nil?
      result[item].minMonth = minMonth
    else
      result[item].minMonth = [minMonth, result[item].minMonth].min
    end
  }
end

###################################################################################################
# Get minimum effective month for every item
def calcMonthCounts()
  result = Hash.new { |h,k| h[k] = 0 }
  ItemEvent.group_and_count(:date).each { |record|
    result[record.date.year*100 + record.date.month] += record[:count]
  }
  return result
end

###################################################################################################
# Calculate a digest of items and people for each month of stats.
def calcStatsMonths()

  puts "Estimating work."
  # Make sure all authors are connected to people
  connectAuthors

  # Determine the size of each month, for time estimation during processing
  puts "  Calculating month counts."
  monthCounts = calcMonthCounts()
  itemSummaries = Hash.new { |h,k| h[k] = ItemSummary.new }

  # Create the mega-digest that summarizes all the items and units and people for each month.
  puts "  Calculating unit digests."
  calcUnitDigests(itemSummaries)

  puts "  Calculating people digests."
  calcPeopleDigests(itemSummaries)

  puts "  Calculating min month for each item."
  calcMinMonths(itemSummaries)

  # Figure out the grand summation digest for each month, by iterating the items in ascending
  # month order and adding all their stuff to a rolling MD5 digester.
  puts "  Grouping by month."
  monthDigests = {}
  prevMonth, digester = nil, nil
  itemSummaries.keys.sort { |a,b|
    (itemSummaries[a].minMonth || 0) <=> (itemSummaries[b].minMonth || 0)
  }.each { |itemID|
    summ = itemSummaries[itemID]
    summ.minMonth.nil? and next
    if prevMonth != summ.minMonth
      prevMonth.nil? or monthDigests[prevMonth] = calcBase64Digest(digester)
      prevMonth, digester = summ.minMonth, Digest::MD5.new
    end
    digester << itemID << summ.unitsDigest.inspect << summ.peopleDigest.inspect
  }
  prevMonth.nil? or monthDigests[prevMonth] = calcBase64Digest(digester)

  # Update the month digests in the database.
  DB.transaction {
    monthDigests.each { |month, digest|
      StatsMonth.create_or_update(month, cur_digest: digest, cur_count: monthCounts[month])
    }
  }
end

###################################################################################################
def calcNextMonth(month)
  my = month / 100
  mm = month % 100
  mm += 1
  if mm > 12
    mm = 1
    my += 1
  end
  return my*100 + mm
end

###################################################################################################
# For stats, we define 'category': a complicated melange of unit type + hierarchy, and item source.
def gatherItemCategories

  # There's an order to things. The first category for an item wins (hence the use of "||=" when
  # adding things to this hash).
  itemCategory = {}

  # Springer and Biomed are easy to identify
  Item.where(source: 'springer').select_map(:id).each { |item| itemCategory[item.to_s] ||= "postprints:Springer" }
  Item.where(source: 'biomed').select_map(:id).each { |item| itemCategory[item.to_s] ||= "postprints:BioMed" }

  # All items from LBNL are considered postprints
  UnitItem.where(unit_id: 'lbnl').distinct.select_map(:item_id).each { |item|
    itemCategory[item] ||= "postprints:LBNL"
  }

  # Campus postprint series are units that have "_postprints" in their name.
  UnitItem.where(Sequel.like(:unit_id, '%_postprints')).distinct.select_map(:item_id).each { |item|
    itemCategory[item] ||= "postprints:campus"
  }

  # Everything in an ETD series is an ETD
  UnitItem.where(Sequel.like(:unit_id, '%_etd')).distinct.select_map(:item_id).each { |item|
    itemCategory[item] ||= "ETDs"
  }

  # Take unit type into consideration
  unitType = {}
  Unit.select_map([:id, :type]).each { |unit, type|
    next if unit == "root"
    unitType[unit] = case type
      when 'campus', 'oru';    "ORU / campus"
      when 'journal';          "journals"
      when 'monograph_series'; "monographic series"
      when 'series';           "series"
      when 'seminar_series';   "seminar series"
      else                     raise("unknown unit type mapping: #{type}")
    end
  }

  UnitItem.where(is_direct: true).order(:ordering_of_units).select_map([:unit_id, :item_id]).each { |unit, item|
    unitType[unit] and itemCategory[item] ||= unitType[unit]
  }

  # Filter out unpublished and no-content items
  ## Unnecessary
  #DB["SELECT id FROM items WHERE status != 'published' OR attrs->'$.suppress_content' is not null"].each { |row|
  #  itemCategory.delete(row[:id])
  #}

  # All done.
  return itemCategory
end

###################################################################################################
# Calculate a digest of items and people for each month of stats.
def propagateItemMonth(itemUnits, itemPeople, itemCategory, monthPosts, month)
  puts "Propagating month #{month}."

  # We will accumulate data into these hashes
  itemStats     = Hash.new { |h,k| h[k] = EventAccum.new }
  unitStats     = Hash.new { |h,k| h[k] = EventAccum.new }
  personStats   = Hash.new { |h,k| h[k] = EventAccum.new }
  categoryStats = Hash.new { |h,k| h[k] = EventAccum.new }

  # First handle item postings for this month
  (monthPosts || []).each { |item|
    itemStats[item].incPost
    itemUnits[item].each { |unit| unitStats[unit].incPost }
    itemPeople[item] and itemPeople[item].each { |pp| personStats[pp].incPost }
    categoryStats[itemCategory[item] || 'unknown'].incPost
  }

  # Next accumulate events for each items accessed this month
  startDate = Date.new(month/100, month%100, 1)
  endDate   = startDate >> 1  # cool obscure operator that adds one month to a date
  ItemEvent.where{date >= startDate}.where{date < endDate}.each { |event|
    accum = EventAccum.new(JSON.parse(event.attrs))
    item = event.item_id
    itemStats[item].add(accum)
    itemUnits[item].each { |unit| unitStats[unit].add(accum) }
    itemPeople[item] and itemPeople[item].each { |pp| personStats[pp].add(accum) }
    categoryStats[itemCategory[item] || 'unknown'].add(accum)
  }

  # Write out all the stats
  DB.transaction {
    ItemStat.where(month: month).delete
    itemStats.each { |item, accum|
      ItemStat.create(item_id: item, month: month, attrs: accum.to_h.to_json)
    }

    UnitStat.where(month: month).delete
    unitStats.each { |unit, accum|
      UnitStat.create(unit_id: unit, month: month, attrs: accum.to_h.to_json)
    }

    PersonStat.where(month: month).delete
    personStats.each { |person, accum|
      PersonStat.create(person_id: person, month: month, attrs: accum.to_h.to_json)
    }

    CategoryStat.where(month: month).delete
    categoryStats.each { |category, accum|
      CategoryStat.create(category: category, month: month, attrs: accum.to_h.to_json)
    }
  }
end

###################################################################################################
# The main routine
#calcStatsMonths

puts "Gathering item categories."
itemCategory = gatherItemCategories

puts "Gathering item-person associations."
itemPeople = ItemAuthor.where(Sequel.~(person_id: nil)).select_hash_groups(:item_id, :person_id)

puts "Gathering item-unit associations."
itemUnits = UnitItem.select_hash_groups(:item_id, :unit_id)
# Attribute all items without a unit directly to root
DB.fetch("SELECT id FROM items WHERE id NOT IN (SELECT item_id FROM unit_items)").each { |row|
  itemUnits[row[:id]] = [ 'root' ]
}

puts "Gathering item posting dates."
monthPosts = Hash.new { |h,k| h[k] = [] }
# Omit non-published and suppress-content items from posting counts.
# NOTE: These numbers differ slightly from old (eschol4) stats because our new code converter
#       (based on normalization stylesheets) has better date calulation for ETDs (using the
#       history.xml file instead of timestamp on meta).
Item.where(status: 'published').
     where(Sequel.lit("attrs->'$.suppress_content' is null")).
     select_map([:id, :attrs]).each { |item, attrStr|
  attrStr.nil? and raise("item #{item} has null attrs")
  sdate = JSON.parse(attrStr)["submission_date"]
  sdate.nil? and raise("item #{item} missing submission_date")
  sdate = parseDate(sdate)
  monthPosts[sdate.year*100 + sdate.month] << item
}

month = 200511
propagateItemMonth(itemUnits, itemPeople, itemCategory, monthPosts[month], month)
