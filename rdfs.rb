#!/usr/bin/env ruby

# RDFS - Ruby Distributed File Sync
# Copyright (C) 2018 Sourcerer, All Rights Reserved
# Written by Robert W. Oliver II - <robert@cidergrove.com>
#
# -- BASIC OVERVIEW --
#
# RDFS monitors for changes within a folder. Once these are detected,
# the files are SHA256 hashed and that hash, along with last-modified
# time is stored in an SQLite3 database. Upon changes, these hashes
# are updated.
#
# Other machines running RDFS can connect to one another and receive
# these updates, therefore keeping multiple directories across different
# machines in sync.
#
# Since the SHA256 hash is calculated, the system avoids saving the same
# block of data twice. This provides a basic data de-duplication scheme.
#
# While RDFS is functional, it is not an ideal construction of a high
# performance, production-ready distrubted file system. Its primary
# focus is to demonstrate the concepts involved in such system and
# serve as a teaching tool for these techniques.
#
# -- LICENSE --
#
# This software is licensed under the GPLv3 or later.
#

# To install requirements on a Debian based system, run:
# apt install ruby-sqlite3 ruby-daemons

require 'digest'
require 'sqlite3'
require 'find'
require 'logger'
require 'webrick'
require 'uri'
require 'net/http'
require 'zlib'
require 'English'
require 'base64'
require 'awesome_print'

require_relative 'lib/updater'
require_relative 'lib/transmitter'
require_relative 'lib/server'

module RDFS
  # CTRL+C Handler
  trap('SIGINT') do
    puts "\nRDFS Shutdown via CTRL+C."
    exit 130
  end

  # If debug is enabled, output will be quite verbose.
  RDFS_DEBUG = true

  # Default RDFS path
  RDFS_PATH = Dir.home + '/rdfs'

  # SQLite3 database file
  RDFS_DB_DIR = Dir.home + "/rdfsdb/"

  HOSTNAME = `hostname`.chomp

  RDFS_DB_FILE = RDFS_DB_DIR + HOSTNAME + ".sqlite3"

  # SQLite3 schema
  RDFS_SCHEMA_FILES = "CREATE TABLE files (
      sha256 VARCHAR(64),
      name VARCHAR(255),
      last_modified INT,
      updated INT,
      deleted INT,
      deleted_done INT);".freeze
  RDFS_SCHEMA_INDEX = "CREATE UNIQUE INDEX `unidx1` ON `files` ( `sha256`, `name` );" +
      "CREATE UNIQUE INDEX `unidxnames` ON `files` ( `name` );"
  RDFS_SCHEMA_NODES = "CREATE TABLE nodes (ip VARCHAR(15));"

  # RDFS path update frequency (in seconds)
  RDFS_UPDATE_FREQ = 5

  # RDFS transmit freq 5

  # RDFS listen port
  RDFS_PORT = 47_656

  # Setup logging
  logger = Logger.new(STDOUT)
  logger.level = RDFS_DEBUG ? Logger::DEBUG : Logger::WARN

  # Output startup message
  puts "RDFS - Ruby Distributed File Sync\n"\
    "Copyright (C) 2018 Sourcerer, All Rights Reserved.\n"\
    "Written by Robert W. Oliver II. Licensed under the GPLv3.\n\n"

  unless Dir.exist?(RDFS_DB_DIR)
    Dir.mkdir(RDFS_DB_DIR)
    logger.info('RDFS directory ' + RDFS_DB_DIR + ' not found, so it was created.')
  end
  # If the database doesn't exist, create it.
  unless File.exist?(RDFS::RDFS_DB_FILE)
    SQLite3::Database.open(RDFS::RDFS_DB_FILE) do |d|
      d.execute RDFS_SCHEMA_FILES
      d.execute RDFS_SCHEMA_NODES
      d.execute RDFS_SCHEMA_INDEX
      d.close
    end
    logger.info('RDFS database was not found, so it was created.')
  end

  # Does file storage area exist?  If not, create it.
  unless Dir.exist?(RDFS_PATH)
    Dir.mkdir(RDFS_PATH)
    logger.info('RDFS directory ' + RDFS_PATH + ' not found, so it was created.')
  end

  # Open the database
  RDFS_DB = SQLite3::Database.open RDFS_DB_FILE

  # Even in production, it's better for RDFS to crash than to have threads die
  # and never run again. Makes it easier to track down issues.
  Thread.abort_on_exception = false
  @update_frequency = RDFS_UPDATE_FREQ
  @running = true


  # Start the server
  Thread.new do
    @server = Server.new
  end

  sleep 2
  # Start the updater
  @updater = Updater.new(RDFS_UPDATE_FREQ)


  # Start the transmitter

  @transmitter = Transmitter.new(RDFS_UPDATE_FREQ)

  while true
    @updater.update_database
    Thread.pass
    sleep @update_frequency

    @transmitter.transmit
    Thread.pass
    sleep @update_frequency

    @updater.check_for_deleted_files
    Thread.pass
    sleep @update_frequency

    @transmitter.transmit
    Thread.pass
    sleep @update_frequency
  end


  puts 'RDFS Shutdown.'
end
