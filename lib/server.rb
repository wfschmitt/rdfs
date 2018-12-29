module RDFS
  class Server < WEBrick::HTTPServlet::AbstractServlet
    attr_accessor :webrick
    attr_accessor :logger

    def initialize
      # Setup logging inside the server
      @logger = Logger.new(STDOUT)
      @logger.level == if RDFS_DEBUG
                         Logger::DEBUG
                       else
                         Logger::WARN
                       end

      @webrick = WEBrick::HTTPServer.new Port: RDFS_PORT
      @webrick.mount '/nodes', Nodes
      @webrick.mount '/files', Files
      @webrick.start
    end
  end

  class Files < WEBrick::HTTPServlet::AbstractServlet
    attr_accessor :logger

    # Process a POST request
    def do_POST(request, response)
      status, content_type, body = api_handler(request)
      response.status = status
      response['Content-Type'] = content_type
      response.body = body
    end

    private

    def api_handler(request)
      # We assume this by default, but can change it as the function progresses
      response_text = 'OK'

      # Grab the IP of the requester
      ip = request.remote_ip

      case request.query['api_call']
      when 'add'
        filename = request.query['filename']
        final_filename = RDFS_PATH + '/' + filename
        # Does the path exist? If not, create it.
        sha256sum = request.query['sha256sum']

        query = RDFS_DB.prepare('SELECT * FROM files WHERE sha256 = :sha256 AND name = :name ')
        query.bind_param('sha256', sha256sum)
        query.bind_param('name', filename)
        row = query.execute

        if row.count > 0
          # this already exists signal sucess
          @logger.warn('add already exits')
          # return [200, 'text/plain', response_text]
        else

          if filename.include?('/')
            FileUtils.mkdir_p(File.dirname(final_filename))
          end
          # Decode, decompress, then save the file
          # We could use better compression, but for now this will work.
          File.write(final_filename, Base64.decode64(request.query['content']))

          # Add it to the local database with updated and deleted set to 0 so that
          # the client's transmitter won't try to send it to possibly non-existent nodes.
          query = RDFS_DB.prepare('INSERT INTO files (name, sha256, last_modified, updated, deleted) VALUES (:name, :sha256, :last_modified, :updated, :deleted)')
          query.bind_param('name', filename)
          query.bind_param('sha256', sha256sum)
          query.bind_param('last_modified', Time.now.to_i)
          query.bind_param('updated', '0')
          query.bind_param('deleted', '0')
          query.execute
      end

      when 'add_dup'
        new_name = request.query['filename']
        sha256sum = request.query['sha256sum']

        # Grab the original filename
        query = RDFS_DB.prepare('SELECT name FROM files WHERE sha256 = :sha256')
        query.bind_param('sha256', sha256sum)
        row = query.execute.first
        if row.count > 0
          old_name = RDFS_PATH + '/' + row[0]
          new_name= RDFS_PATH + '/' +new_name
          testxx = (new_name <=> old_name)
          if testxx.zero?
            @logger.warn('dont copy on my self')
          else
            FileUtils.cp(old_name, new_name)
          end

        else
          # SHA256 not found
          # File deleted after query but before add_dup?
          response_text = 'NOT_FOUND'
        end

      when 'delete'
        # Delete file was called
        filename = request.query['filename']
        full_filename = RDFS_PATH + '/' + filename
        # Does the file exist?
        if File.exist?(full_filename)
          # Is it a directory? If so, handle it separately.
          if File.directory?(full_filename)
            FileUtils.rmdir(full_filename)
          else
            # Force deletion of a file.
            FileUtils.rm_f(full_filename)
          end
        else
          response_text = 'NOT_FOUND'
        end

      when 'add_query'
        # Check if duplicate exists
        sha256sum = request.query['sha256sum']
        query = RDFS_DB.prepare('SELECT sha256 FROM files WHERE sha256 = :sha256')
        query.bind_param('sha256', sha256sum)
        row = query.execute
        response_text = if row.count > 0
                          'EXISTS'
                        else
                          'NOT_FOUND'
                        end
      end

      [200, 'text/plain', response_text]
    end
  end

  class Nodes < WEBrick::HTTPServlet::AbstractServlet
    attr_accessor :logger

    # Process a POST request
    def do_POST(request, response)
      status, content_type, body = api_handler(request)
      response.status = status
      response['Content-Type'] = content_type
      response.body = body
    end

    private

    def api_handler(request)
      # We assume this by default, but can change it as the function progresses
      response_text = 'OK'

      # Grab the IP of the requester
      ip = request.remote_ip

      case request.query['api_call']
        # Add a node
      when 'add_node'
        query = RDFS_DB.prepare('SELECT ip FROM nodes WHERE ip = :ip')
        query.bind_param('ip', ip)
        row = query.execute
        if row.count > 0
          response_text = 'Node with IP ' + ip + " was already registered.\n"
        else
          query = RDFS_DB.prepare('INSERT INTO nodes (ip) VALUES (:ip)')
          query.bind_param('ip', ip)
          query.execute
          response_text = 'Node with IP ' + ip + " added.\n"
        end
        # Remove a node
      when 'delete_node'
        query = RDFS_DB.prepare('DELETE FROM nodes WHERE ip = :ip')
        query.bind_param('ip', ip)
        query.execute
        response_text = 'Node with IP ' + ip + " removed.\n"
      end

      [200, 'text/plain', response_text]
    end

    # Create SHA256 of a file
    def sha256file(file)
      Digest::SHA256.file(file).hexdigest
    end
  end
end
