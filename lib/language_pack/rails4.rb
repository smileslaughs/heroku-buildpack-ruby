require "language_pack"
require "language_pack/rails3"

# Rails 4 Language Pack. This is for all Rails 4.x apps.
class LanguagePack::Rails4 < LanguagePack::Rails3
  ASSETS_CACHE_LIMIT = 52428800 # bytes

  # detects if this is a Rails 4.x app
  # @return [Boolean] true if it's a Rails 4.x app
  def self.use?
    instrument "rails4.use" do
      rails_version = bundler.gem_version('railties')
      return false unless rails_version
      is_rails4 = rails_version >= Gem::Version.new('4.0.0.beta') &&
                  rails_version <  Gem::Version.new('4.1.0.beta1')
      return is_rails4
    end
  end

  def name
    "Ruby/Rails with .lateslugignore support"
  end

  def default_process_types
    instrument "rails4.default_process_types" do
      super.merge({
        "web"     => "bin/rails server -p $PORT -e $RAILS_ENV",
        "console" => "bin/rails console"
      })
    end
  end

  def build_bundler
    instrument "rails4.build_bundler" do
      super
    end
  end

  def compile
    instrument "rails4.compile" do
      slug_ignore '.earlyslugignore'
      super
      slug_ignore '.lateslugignore'
    end
  end

  private

  def install_plugins
    instrument "rails4.install_plugins" do
      return false if bundler.has_gem?('rails_12factor')
      plugins = ["rails_serve_static_assets", "rails_stdout_logging"].reject { |plugin| bundler.has_gem?(plugin) }
      return false if plugins.empty?

    warn <<-WARNING
Include 'rails_12factor' gem to enable all platform features
See https://devcenter.heroku.com/articles/rails-integration-gems for more information.
WARNING
    # do not install plugins, do not call super
    end
  end

  def public_assets_folder
    "public/assets"
  end

  def default_assets_cache
    "tmp/cache/assets"
  end

  def run_assets_precompile_rake_task
    instrument "rails4.run_assets_precompile_rake_task" do
      log("assets_precompile") do
        if Dir.glob('public/assets/manifest-*.json').any?
          puts "Detected manifest file, assuming assets were compiled locally"
          return true
        end

        precompile = rake.task("assets:precompile")
        return true unless precompile.is_defined?

        topic("Preparing app for Rails asset pipeline")

        @cache.load public_assets_folder
        @cache.load default_assets_cache

        precompile.invoke(env: rake_env)

        if precompile.success?
          log "assets_precompile", :status => "success"
          puts "Asset precompilation completed (#{"%.2f" % precompile.time}s)"

          puts "Cleaning assets"
          rake.task("assets:clean").invoke(env: rake_env)

          cleanup_assets_cache
          @cache.store public_assets_folder
          @cache.store default_assets_cache
        else
          precompile_fail(precompile.output)
        end
      end
    end
  end

  def cleanup_assets_cache
    instrument "rails4.cleanup_assets_cache" do
      LanguagePack::Helpers::StaleFileCleaner.new(default_assets_cache).clean_over(ASSETS_CACHE_LIMIT)
    end
  end
  
  # I needed this to clean assets before my slug compilation on heroku.  This basically reimplements
  # the heroku change #179 (http://goo.gl/m5QIL) that was rolled back by heroku change #185 (http://goo.gl/miPpK)
  # It should be pretty generic -- it looks for extensions to purge from a .lateslugignore file in the RoR root.
  #
  # If you have any questions, feel free to hunt me down: pg8p@virginia.edu
  
  def slug_ignore(filename='.lateslugignore')
    # Meh, I should log something here.
    if File.exist?(filename)
      topic("Beep Bloop. Processing your #{filename} file!.")
      ignored_extensions = Array.new
    
      late_slug_ignore_file = File.new("#{filename}", "r")
      late_slug_ignore_file.each do |line|
      	next if line.nil?
      	line.chomp!
      	next if "#{line}".empty?
      	
	  	ignored_extensions.push line
      end
      late_slug_ignore_file.close
    
      matched_files = Array.new
      ignored_extensions.each {|ext| matched_files.push Dir.glob(File.join("**",ext))}
      matched_files.flatten!
      puts "Deleting #{matched_files.count} files matching #{filename} patterns."
      matched_files.each { |f| File.delete(f) unless File.directory?(f) }
    
      # For what it's worth, I wrote an asset cleaning tool, but it's not generic enough for general use, but I bet
      # it probably does a better job achieving a completely clean asset configuration when used in tandem with
      # asset_sync -- then again, I've only lightly considered this.  Anyway, if someone cares to improve this, the
      # code is sitting right below
      #
      #puts "Running rake assets:clean"
      #require 'benchmark'
      #time = Benchmark.realtime { pipe("env PATH=$PATH:bin bundle exec rake assets:clean 2>&1") }
      #if $?.success?
      #  # Really, for the love of god, why does the string formatting look so crazy???
      #  puts "Assets cleaned from compilation location in (#{"%.2f" % time}s)."
      #else
      #  puts "Asset cleansing failed.  Yikes."
      #end
      #puts "Dropping assets from app/assets, lib/assets, and vendor/assets."
      #FileUtils.rm_rf("app/assets")
      #FileUtils.rm_rf("lib/assets")
      #FileUtils.rm_rf("vendor/assets")
      #puts "All assets removed from the slug."
    else
      topic("Beep Bloop. Failed to find your #{filename} file!.  Is it in your applications root directory?")
    end
  end
end
