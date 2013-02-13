# encoding: utf-8

module Backup
  class Archive
    include Backup::CLI::Helpers

    ##
    # Stores the name of the archive
    attr_reader :name

    ##
    # Stores an array of different paths/files to store
    attr_reader :paths

    ##
    # Stores an array of different paths/files to exclude
    attr_reader :excludes

    ##
    # Stores string of additional arguments for the `tar` command
    attr_reader :tar_args

    ##
    # Stores option to allow changed files
    attr_reader :allow_exit1

    ##
    # Takes the name of the archive and the configuration block
    def initialize(model, name, &block)
      @model    = model
      @name     = name.to_s
      @paths    = Array.new
      @excludes = Array.new
      @tar_args = ''
      @allow_exit1 = false

      instance_eval(&block) if block_given?
    end

    ##
    # Adds new paths to the @paths instance variable array
    def add(path)
      path = File.expand_path(path)
      if File.exist?(path)
        @paths << path
      else
        Logger.warn Errors::Archive::NotFoundError.new(<<-EOS)
          The following path was not found:
          #{ path }
          This path will be omitted from the '#{ name }' Archive.
        EOS
      end
    end

    ##
    # Adds new paths to the @excludes instance variable array
    def exclude(path)
      @excludes << File.expand_path(path)
    end

    ##
    # Adds the given String of +options+ to the `tar` command.
    # e.g. '-h --xattrs'
    def tar_options(options)
      @tar_args = options
    end

    ##
    # Allows an archive with files that were changed during the archive
    # process to complete successfully. i.e. allows `tar` exit status 1
    #
    # Note that the archive job will still log a warning should this occur.
    # You may add `--warning=no-file-changed` to `tar_options` if you wish
    # to supress these warnings.
    def allow_changed_files(val = true)
      @allow_exit1 = val
    end

    ##
    # Archives all the provided paths in to a single .tar file
    # and places that .tar file in the folder which later will be packaged
    # If the model is configured with a Compressor, the tar command output
    # will be piped through the Compressor command and the file extension
    # will be adjusted to indicate the type of compression used.
    def perform!
      Logger.info "#{ self.class } has started archiving:\n" +
          paths.map {|path| "  #{path}" }.join("\n")

      archive_path = File.join(Config.tmp_path, @model.trigger, 'archives')
      FileUtils.mkdir_p(archive_path)

      archive_ext = 'tar'
      pipeline = Pipeline.new

      pipeline.add(
        "#{ utility(:tar) } #{ tar_args } -cPf - " +
        "#{ paths_to_exclude } #{ paths_to_package }",
        allow_exit1 ? [0, 1] : [0]
      )

      if @model.compressor
        @model.compressor.compress_with do |command, ext|
          pipeline << command
          archive_ext << ext
        end
      end

      pipeline << "cat > '#{ File.join(archive_path, "#{name}.#{archive_ext}") }'"
      pipeline.run
      if pipeline.success?
        Logger.info "#{ self.class } Complete!"
      else
        raise Errors::Archive::PipelineError,
            "Failed to Create Backup Archive\n" +
            pipeline.error_messages
      end
    end

    private

    ##
    # Returns a "tar-ready" string of all the specified paths combined
    def paths_to_package
      paths.map {|path| "'#{path}'" }.join(' ')
    end

    ##
    # Returns a "tar-ready" string of all the specified excludes combined
    def paths_to_exclude
      if excludes.any?
        excludes.map {|path| "--exclude='#{path}'" }.join(' ')
      end
    end

  end
end
