module RDFS
  class Transmitter
    attr_accessor :main_thread

    # Called upon Transmitter.new
    def initialize(transmit_frequency)
      @transmit_frequency = transmit_frequency
      @running = 1
      # Setup logging inside the updater
      @logger = Logger.new(STDOUT)
      @logger.level = RDFS_DEBUG ? Logger::DEBUG : Logger::WARN
      @logger.progname = 'transmitter'.yellow
      @loglvl = Logger::WARN
      @logger.warn {'Transmitter thread started.'.yellow}
      # Create the thread
      @main_thread = Thread.new kernel

    end

    # Stop the transmitter
    def stop
      @running = nil
    end

    private

    attr_writer :running
    attr_accessor :logger

    def kernel
      while @running
        # Transmit
        transmit

        Thread.pass
        sleep @transmit_frequency
      end
    end

    # Reads a binary file and returns its contents in a string
    def read_file(file)
      file = File.open(file, 'rb')
      file.read
    end

    # Create SHA256 of a file
    def sha256file(file)
      Digest::SHA256.file(file).hexdigest
    end

    # Transmit
    def transmit
      # First, check to see if there are any active nodes. If not, there's no
      # point in wasting DB time in checking for updated files.
      # This could use some refactoring.
      sql = 'SELECT * FROM nodes'
      nodes_row = RDFS_DB.execute(sql)
      if nodes_row.count > 0
        sql = 'SELECT * FROM files WHERE updated != 0 OR deleted != 0'
        @logger.add(@loglvl) {sql}
        row = RDFS_DB.execute(sql)
        @logger.add(@loglvl) {"todo: #{row.count} "}
        if row.count > 0
          nodes_row.each do |node|
            row.each do |file|
              ip = node[0]
              sha256sum = file[0]
              filename = file[1]
              updated = file[3]
              deleted = file[4]
              # Check to see if the file exists using some other filename.
              # If it does, we make a call to add without actually sending the file.
              uri = URI.parse('http://' + ip + ':' + RDFS_PORT.to_s + '/files')
              if (updated != 0) && (deleted == 0)
                # UPDATE
                begin
                  response = Net::HTTP.post_form(uri, 'api_call' => 'add_query',
                                                 'filename' => filename, 'sha256sum' => sha256sum)
                  if response.body.include?('EXISTS')
                  # File exists but with a different filename, so call the add_dup
                  # function to avoid using needless bandwidth
                    response = Net::HTTP.post_form(uri,
                                                   'api_call' => 'add_dup',
                                                   'filename' => filename,
                                                   'sha256sum' => sha256sum)
                    if response.body.include?('OK')
                      clear_update_flag(filename)
                      next
                    end
                  end
                rescue StandardError
                  @logger.warn {'Unable to connect to node at IP ' + ip + '.'}
                end
                begin
                    # File doesn't exist on node, so let's push it.
                    # Read it into a string (this will have to be improved at some point)
                  file_contents = read_file(RDFS_PATH + '/' + filename)
                  file_contents = Base64.encode64(file_contents)
                    # Then push it in a POST call
                  response = Net::HTTP.post_form(uri,
                                                   'api_call' => 'add',
                                                   'filename' => filename,
                                                   'sha256sum' => sha256sum,
                                                   'content' => file_contents)
                  clear_update_flag(filename) if response.body.include?('OK')
                rescue StandardError
                  @logger.warn {'Unable to transfer to node at IP ' + ip + '.'}
                end
              end
              next if deleted == 0

              # DELETED
              begin
                response = Net::HTTP.post_form(uri,
                                               'api_call' => 'delete',
                                               'filename' => filename,
                                               'sha256sum' => sha256sum)
                if response.body.include?('OK')
                  clear_update_flag(filename)
                  set_deleted_flag(filename)
                else
                  # todo:
                  @logger.warn {'delete failed remote ' + request.body}
                end
              rescue StandardError
                @logger.warn {'Unable to connect to node at IP ' + ip + '.'}
              end
            end
          end
        end
      end
    end

    # Reads a binary file and returns its contents in a string
    def read_file(file)
      file = File.open(file, 'rb')
      file.read
    end

    # Clears the updated/deleted flags
    def clear_update_flag(filename)
      sql = 'UPDATE files SET updated = 0, deleted = 0, deleted_done = 0 WHERE name ="' + filename.to_s + '"'
      @logger.add(@loglvl) {sql}
      RDFS_DB.execute(sql)
    end


    # Clears the updated/deleted flags
    def set_deleted_flag(filename)
      sql = 'UPDATE files SET updated = 0, deleted = 0, deleted_done = 1 WHERE name ="' + filename.to_s + '"'
      @logger.add(@loglvl) {sql}
      RDFS_DB.execute(sql)
    end
  end
end
