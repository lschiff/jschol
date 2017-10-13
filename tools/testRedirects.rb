#!/usr/bin/env ruby

require 'uri'

def error(msg)
  puts "Error: #{msg}"
  exit 1
end

def testRedirect(fromURL, toURL)
  uri = URI.parse(fromURL)
  host = uri.host
  cmd = %{curl --silent --resolve #{host}:4001:127.0.0.1 -I "#{fromURL.sub(/:\/\/([^\/]+)/, '://\1:4001')}"}
  result = `#{cmd}`.encode!('UTF-8', 'UTF-8', :invalid => :replace)
  if result =~ %r{HTTP/1.1 (30[123]).*Location: ([^\n]+)}m
    got = $2.strip
    toURL == got or error("Incorrect redirect. #{fromURL.inspect} -> #{got.inspect} but expected #{toURL.inspect}")
  elsif result =~ %r{HTTP/1.1 (\d+)}
    code = $1.to_i
    if code == 200
      return if toURL.nil?
      error "#{fromURL.inspect} got 200, should have redirected to #{toURL.inspect}"
    else
      error "error #{$1} from #{fromURL.inspect}"
    end
  else
    puts cmd
    error "huh? #{fromURL.inspect} #{result.inspect}"
  end
end

# DOJ redirects
testRedirect("http://dermatology.cdlib.org//143/index.html",
             "https://escholarship.org/uc/doj/14/3")
testRedirect("http://dermatology.cdlib.org//102/case_presentations/pseudomonas/2.jpg",
             "https://escholarship.org/uc/item/6fz6c3r8")
testRedirect("http://dermatology.cdlib.org//search?uri=1&go=1&entity=doj&keyword=Search%20journal...&q=1&scope=../../../../../../../../../../../../../../../../etc/passwd",
             "https://escholarship.org/uc/doj")

# Bepress redirects
testRedirect("http://repositories.cdlib.org/uctc",
             "https://escholarship.org/uc/uctc")
testRedirect("http://repositories.cdlib.org/its/tsc",
             "https://escholarship.org/uc/its_tsc")
testRedirect("http://repositories.cdlib.org/acgcc/jtas/vol1/iss1/art8",
             "https://escholarship.org/uc/item/4035s7ss")
testRedirect("http://repositories.cdlib.org//acgcc/jtas/emoryelliott.html",
             "https://escholarship.org/uc/acgcc_jtas")
testRedirect("http://repositories.cdlib.org/cgi/viewcontent.cgi?article=1006&context=its/tsc",
             "https://escholarship.org/uc/item/0201j0v2")
testRedirect("http://repositories.cdlib.org/context/tc/article/1194/type/pdf/viewcontent",
             "https://escholarship.org/uc/item/8hk6960q")
testRedirect("http://repositories.cdlib.org//cgi/viewcontent.cgi?context=its/tsc&amp;article=1045",
             "https://escholarship.org/uc/item/1h52s226")

# Programmed unit redirects from unitRedirect.xsl
testRedirect("http://escholarship.org/uc/ioe",
             "https://escholarship.org/uc/ioes")

# Unit to landing page
testRedirect("http://escholarship.org/uc/search?entity=uciem_westjem",
             "https://escholarship.org/uc/uciem_westjem")

# Journal issue
testRedirect("http://escholarship.org/uc/search?entity=uciem_westjem;volume=18;issue=6.1",
             "https://escholarship.org/uc/uciem_westjem/18/6.1")

# Keyword search
testRedirect("http://escholarship.org/uc/search?keyword=japan",
             "https://escholarship.org/search?q=japan")

# Redirect eScholarship Editions
testRedirect("http://escholarship.org/editions/view?docId=ft6d5nb46p&chunk.id=nsd0e372&toc.id=endnotes&toc.depth=1&brand=ucpress&anchor.id=d0e436",
             "https://publishing.cdlib.org/ucpressebooks/view?docId=ft6d5nb46p&chunk.id=nsd0e372&toc.id=endnotes&toc.depth=1&brand=ucpress&anchor.id=d0e436")

# Redirect garbled or old searches
testRedirect("http://escholarship.org/uc/item/3nm3m1rv?query=%E5%98%97%E9%BA%A5&hitNum=1&scroll=yes",
             "https://escholarship.org/uc/item/3nm3m1rv")

# Redirect pvw item to main item
testRedirect("http://pvw.escholarship.org/uc/item/5j20j32b",
             "https://escholarship.org/uc/item/5j20j32b")

# Redirect eprints to eschol
testRedirect("http://eprints.cdlib.org/uc/item/8gj3x1dc",
             "https://escholarship.org/uc/item/8gj3x1dc")

# Redirect eschol.cdlib
testRedirect("http://escholarship.cdlib.org/uc/item/9ws876kn.pdf",
             "https://escholarship.org/uc/item/9ws876kn.pdf")

# Redirect old PDF links
testRedirect("http://escholarship.org/uc/item/4590m805.pdf",
             "https://cloudfront.escholarship.org/dist/prd/content/qt4590m805/qt4590m805.pdf")

# No longer redirecting PDF links
testRedirect("http://escholarship.org/content/qt4590m805/qt4590m805.pdf", nil)

# Redirect from supp file to item
testRedirect("http://escholarship.org/uc/item/3kq9770m/socr_pt4_20070806_v256_part_2.mpg",
             "https://escholarship.org/uc/item/3kq9770m")

# Strip query parameters from item URLs
testRedirect("http://escholarship.org/uc/item/0nm3g51w?foo=bar",
             "https://escholarship.org/uc/item/0nm3g51w")

# Specific item to item redirects
testRedirect("http://escholarship.org/uc/item/0fz9h5rt",
             "https://escholarship.org/uc/item/13x9v6ms")

# Redirect www.escholarship to escholarship
testRedirect("http://www.escholarship.org",
             "https://escholarship.org/")
testRedirect("http://www.escholarship.org/uc/uclta",
             "https://escholarship.org/uc/uclta")
testRedirect("http://www.escholarship.org/uc/uclta?foo=bar",
             "https://escholarship.org/uc/uclta?foo=bar")
