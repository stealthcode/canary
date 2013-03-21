require_relative 'canary/task'
require_relative 'canary/story'
require_relative 'canary/script'
require_relative 'canary/domain'
require_relative 'canary/rspec'
require_relative 'canary/mongo'
require_relative 'canary/story_logger'

require 'capybara/poltergeist'
require 'rspec'
require 'json'

module Canary
  class << self
    attr_reader :story_list, :data_connections, :config, :categories, :active_suite
    attr_accessor :setup_story, :testing_phase, :active_page, :factory_class, :config_path, :phantomjs_headers,
                  :debug_mode

    def initialize(&setup)
      @story_list = []
      @testing_phase = :not_started
      @active_page = Canary::Page::AbstractPage
      @categories = {}
      @categories_array = []
      @last_category_id = 0
      @config_file_name = 'config.yaml'
      @poltergeist_logger = AggregateLogger.new()
      @poltergeist_options = {:logger => @poltergeist_logger}
      @debug_mode = false
      setup.call(self) unless setup.nil?
      configure
      @service = MongoDBService.new(Canary.config['MongoDbHost'], Canary.config['MongoDbPort'])
      @active_suite = TestSuite.new(@service)
      ::RSpec.configure do |config|
        config.include(Canary::Script)
        config.add_formatter Canary::RSpec::StoryManager
        config.add_formatter Canary::RSpec::ConsoleReporter
      end
    end

    def poltergeist_options=(hash)
      @poltergeist_options = hash
      @poltergeist_logger.add(hash[:logger]) if hash.has_key?(:logger)
      @poltergeist_options[:logger] = @poltergeist_logger
    end

    def active_story
      if @testing_phase == :setup
        @setup_story
      else
        @story_list.last
      end
    end

    def new_suite
      @active_suite = TestSuite.new(@service)
    end

    def configure
      @config = {
          'TargetEnvironment' => 'localhost',
          'Browser' => 'Poltergeist',
          'MongoDbName' => 'autotest',
          'MongoDbHost' => 'localhost',
          'MongoDbPort' => '27017',
          'ImageContentType' => 'image/png',
          'ImageExt' => 'png'
      }
      config_path = @config_path || Dir.pwd

      begin
        config_file_name = File.expand_path(File.join(config_path, @config_file_name))
        file = File.open(config_file_name)
        yaml = YAML::load(file)
      ensure
        file.close unless file.nil?
      end

      override_config = yaml[ENV['env'].to_s]
      override_config = yaml[ENV['COMPUTERNAME'].to_s] if override_config.nil?
      override_config = yaml[ENV['USERNAME'].to_s] if override_config.nil?
      override_config = yaml['local'] if override_config.nil?
      @config.merge!(override_config)

      targets_file_name = File.expand_path(File.join(config_path, 'targets.yaml'))
      file = File.open(targets_file_name)
      target_yaml = YAML::load(file)
      @config.merge! target_yaml[@config['TargetEnvironment']]

      @data_connections = {}
      @config['Database'].each { |db, values|
        integratedSecurity = !values.include?('username')

        connection = integratedSecurity ?
          Data::ADOSQLDataConnection.connection(values['host']) :
          Data::ADOSQLDataConnection.credential_connection(values['username'], values['password'], values['host'])

        @data_connections[db.to_sym] = Data::ADOSQLDataConnection.new(connection)
      }
      setup_dependencies
    end

    def setup_dependencies
      if @config['Browser'].downcase.include? 'poltergeist'
        Capybara.configure do |config|
          config.default_driver = :poltergeist
        end

        Capybara.register_driver :poltergeist do |app|
          Capybara::Poltergeist::Driver.new(app, @poltergeist_options)
        end
        Capybara.page.driver.headers = phantomjs_headers
      else
        Capybara.configure do |config|
          config.default_driver = :selenium
        end
      end
    end

    def add_category(example)
      tmp = list_of_nested_groups(example)
      iter = @categories
      tmp.reverse_each{ |category|
        unless iter.has_key?(category)
          @last_category_id += 1
          iter[category] = {"id" => @last_category_id}
          @categories_array << category
        end
        iter = iter[category]
      }
      iter["id"]
    end

    def list_of_nested_groups(example)
      tmp = []
      group = example.metadata[:example_group]
      until group.nil?
        tmp.push group[:description]
        group = group[:example_group]
      end
      tmp
    end

    def find_system_versions
      all_versions = {}
      Canary.config['TrackedApplications'].each{|r|
        app = {'app_name' => r[0], 'path' => r[1]}
        app.merge!({'remote_host' => r[2], 'username' => r[3], 'password' => r[4]}) if r.length > 2

        cmd = "(Get-Command #{app['path']}).FileVersionInfo.FileVersion"
        x = Canary::Exec::InlinePowershellCommand.new(cmd, app['remote_host'] || :default)
        result = ''
        begin
          result = x.execute_job
          result = result[/((\d\.)+\d)/, 0] || 'Failed'
        rescue => e
          result = e.message
        end
        all_versions.merge! app['app_name'] => {'version' => result}
      }
      all_versions
    end

    def temp_file_path
      default = File.expand_path(File.join(Dir.pwd, 'tmp'))
      return Canary.config['ScreenshotFolder'] || ENV['AUTOTEST_SAVE_PATH'] || default
    end
  end
end