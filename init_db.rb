#!/usr/bin/ruby

require 'sqlite3'

begin

  myhostname =`hostname`.chomp

  db = SQLite3::Database.open(@dbnam=File.join(Dir.home,"rdfsdb", myhostname + ".sqlite3"))

  db.transaction
  db.execute "DROP TABLE IF EXISTS Friends"
  db.execute "CREATE TABLE Friends(Id INTEGER PRIMARY KEY, Name TEXT)"
  db.execute "INSERT INTO Friends(Name) VALUES ('Tom')"
  db.execute "INSERT INTO Friends(Name) VALUES ('Rebecca')"
  db.execute "INSERT INTO Friends(Name) VALUES ('Jim')"
  db.execute "INSERT INTO Friends(Name) VALUES ('Robert')"
  db.execute "INSERT INTO Friends(Name) VALUES ('Julian')"
  db.execute "INSERT INTO Friends(Name) VALUES ('Michael')"
  db.commit

rescue SQLite3::Exception => e

  puts "Exception occurred"
  puts e
  db.rollback

ensure
  db.close if db
end
