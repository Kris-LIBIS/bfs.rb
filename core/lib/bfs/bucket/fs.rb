require 'bfs'
require 'fileutils'
require 'pathname'

module BFS
  module Bucket
    # FS buckets are operating on the file system
    class FS < Abstract
      def initialize(root, _opts={})
        @root = Pathname.new(root.to_s)
        @prefix = "#{@root.to_s.chomp('/')}/"
      end

      # Lists the contents of a bucket using a glob pattern
      def ls(pattern='**/*', _opts={})
        Enumerator.new do |y|
          Pathname.glob(@root.join(pattern)) do |pname|
            y << trim_prefix(pname.to_s) if pname.file?
          end
        end
      end

      # Info returns the info for a single file
      def info(path, _opts={})
        full = @root.join(norm_path(path))
        path = trim_prefix(full.to_s)
        BFS::FileInfo.new(path, full.size, full.mtime, nil, {})
      rescue Errno::ENOENT
        raise BFS::FileNotFound, path
      end

      # Creates a new file and opens it for writing
      def create(path, _opts={}, &block)
        full = @root.join(norm_path(path))
        FileUtils.mkdir_p(full.dirname.to_s)

        temp = BFS::TempWriter.new(full) {|t| FileUtils.mv t, full.to_s }
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
        full = @root.join(path)
        full.open('r', opts, &block)
      rescue Errno::ENOENT
        raise BFS::FileNotFound, path
      end

      # Deletes a file.
      def rm(path, _opts={})
        full = @root.join(norm_path(path))
        FileUtils.rm_f full.to_s
      end

      # Copies a file.
      def cp(src, dst, _opts={})
        full_src = @root.join(norm_path(src))
        full_dst = @root.join(norm_path(dst))
        FileUtils.mkdir_p full_dst.dirname.to_s
        FileUtils.cp full_src.to_s, full_dst.to_s
      rescue Errno::ENOENT
        raise BFS::FileNotFound, norm_path(src)
      end

      # Moves a file.
      def mv(src, dst, _opts={})
        full_src = @root.join(norm_path(src))
        full_dst = @root.join(norm_path(dst))
        FileUtils.mkdir_p full_dst.dirname.to_s
        FileUtils.mv full_src.to_s, full_dst.to_s
      rescue Errno::ENOENT
        raise BFS::FileNotFound, norm_path(src)
      end

      private

      def trim_prefix(path)
        path.slice!(0, @prefix.size) if path.slice(0, @prefix.size) == @prefix
        path
      end
    end
  end
end

BFS.register('file') do |url|
  parts = [url.host, url.path].compact
  BFS::Bucket::FS.new File.join(*parts)
end
