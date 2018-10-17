require 'bfs'
require 'aws-sdk-s3'
require 'cgi'

module BFS
  module Bucket
    # S3 buckets are operating on s3
    class S3 < Abstract
      attr_reader :name, :sse, :acl, :storage_class

      # Initializes a new S3 bucket
      # @param [String] name the bucket name
      # @param [Hash] opts options
      # @option opts [String] :region default region
      # @option opts [String] :sse default server-side-encryption setting
      # @option opts [Aws::Credentials] :credentials credentials object
      # @option opts [String] :access_key_id custom AWS access key ID
      # @option opts [String] :secret_access_key custom AWS secret access key
      # @option opts [Symbol] :acl canned ACL
      # @option opts [String] :storage_class storage class
      # @option opts [Aws::S3::Client] :client custom client, uses default_client by default
      def initialize(name, opts={})
        opts = opts.dup
        opts.keys.each do |key|
          opts[key.to_s] = opts.delete(key)
        end

        @name = name
        @sse = opts['sse'] || opts['server_side_encryption']
        @credentials = opts['credentials']
        @credentials ||= Aws::Credentials.new(opts['access_key_id'].to_s, opts['secret_access_key'].to_s) if opts['access_key_id']
        @acl = opts['acl'].to_sym if opts.key?('acl')
        @storage_class = opts['storage_class']
        @client = opts['client'] || Aws::S3::Client.new(region: opts['region'])
      end

      # Lists the contents of a bucket using a glob pattern
      def ls(pattern='**/*', opts={})
        @client.list_objects_v2(opts.merge(bucket: name)).contents.select do |obj|
          File.fnmatch?(pattern, obj.key, File::FNM_PATHNAME)
        end.map(&:key)
      end

      # Info returns the object info
      def info(path, opts={})
        path = norm_path(path)
        opts = opts.merge(
          bucket: name,
          max_keys: 1,
          prefix: opts[:prefix] ? File.join(opts[:prefix], path) : path,
        )
        object = @client.list_objects_v2(opts).contents.first
        raise BFS::FileNotFound, path unless object

        BFS::FileInfo.new(path, object.size, object.last_modified)
      rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NoSuchBucket
        raise BFS::FileNotFound, path
      end

      # Creates a new file and opens it for writing
      def create(path, opts={}, &block)
        path = norm_path(path)
        opts = opts.merge(
          bucket: name,
          key: path,
        )
        opts[:acl] ||= @acl if @acl
        opts[:server_side_encryption] ||= @sse if @sse
        opts[:storage_class] ||= @storage_class if @storage_class

        temp = BFS::TempWriter.new(path) do |t|
          File.open(t) do |file|
            @client.put_object(opts.merge(body: file))
          end
        end
        return temp unless block

        begin
          yield temp
        ensure
          temp.close
        end
      end

      # Opens an existing file for reading
      def open(path, opts={}, &block)
        path = norm_path(path)
        temp = Tempfile.new(File.basename(path))
        temp.close

        opts = opts.merge(
          response_target: temp.path,
          bucket: name,
          key: path,
        )
        @client.get_object(opts)

        File.open(temp.path, &block)
      rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NoSuchBucket
        raise BFS::FileNotFound, path
      end

      # Deletes a file.
      def rm(path, opts={})
        path = norm_path(path)
        opts = opts.merge(
          bucket: name,
          key: path,
        )
        @client.delete_object(opts)
      rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NoSuchBucket # rubocop:disable Lint/HandleExceptions
      end

      # Copies a file.
      def cp(src, dst, opts={})
        src = norm_path(src)
        dst = norm_path(dst)
        opts = opts.merge(
          bucket: name,
          copy_source: "/#{name}/#{src}",
          key: dst,
        )
        @client.copy_object(opts)
      rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NoSuchBucket
        raise BFS::FileNotFound, src
      end
    end
  end
end

BFS.register('s3') do |url|
  params = CGI.parse(url.query.to_s)

  BFS::Bucket::S3.new url.host,
    region: params.key?('region') ? params['region'].first : nil,
    sse: params.key?('sse') ? params['sse'].first : nil,
    access_key_id: params.key?('access_key_id') ? params['access_key_id'].first : nil,
    secret_access_key: params.key?('secret_access_key') ? params['secret_access_key'].first : nil,
    acl: params.key?('acl') ? params['acl'].first : nil,
    storage_class: params.key?('storage_class') ? params['storage_class'].first : nil
end
