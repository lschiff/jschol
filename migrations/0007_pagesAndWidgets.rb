# Refactoring 'pages' to better reflect actual UI layout needs.
Sequel.migration do
  up do
    # Combining 'widgets' and 'sidebars' into a single 'widgets' table with a 'region' column
    drop_table :sidebars
    add_column :widgets, :region, :type=>String, :null=>false

    # Refactoring 'pages'
    drop_table :static_queries
    alter_table :pages do
      drop_column :parent_page
      drop_column :date
      drop_column :html
      add_column :ordering, :type=>Integer, :null=>false
      add_column :nav_element, :type=>String, :null=>false
      add_column :attrs, :type=>'JSON'
      add_index [:unit_id, :nav_element, :ordering], :unique=>true
    end
  end

  down do
    raise """It's non-trivial to create the going-back code, and I think we're never going back.
             I hate writing code that will never be tested. Signed, Martin."""
  end
end
