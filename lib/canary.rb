require_relative 'canary/task'
require_relative 'canary/story'
require_relative 'canary/script'
require_relative 'canary/rspec'
require 'capybara/poltergeist'
require 'rspec'
require 'json'

module Canary
  class << self
    attr_reader :test_suite, :data_connections, :config, :categories, :categories_array
    attr_accessor :setup_story, :testing_phase, :active_page, :factory_class, :config_path, :poltergeist_options,
                  :phantomjs_headers

    def initialize(&setup)
      @test_suite = []
      @testing_phase = :not_started
      @active_page = Canary::Page::AbstractPage
      @categories = {}
      @categories_array = []
      @last_category_id = 0
      @config_file_name = 'config.yaml'
      setup.call(self)
      configure
    end

    def new_story
      Story.new(@factory_class.new)
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
        @data_connections[db.to_sym] = Data::SQLDataConnection.new(values['username'], values['password'], values['host'])
      }
      setup_dependencies
    end

    def setup_dependencies
      if @config['Browser'].downcase.include? 'poltergeist'
        Capybara.configure do |config|
          config.default_driver = :poltergeist
        end

        Capybara.register_driver :poltergeist do |app|
          Capybara::Poltergeist::Driver.new(app, poltergeist_options)
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

    def active_test
      if @testing_phase == :setup
        @setup_story
      else
        @test_suite.last
      end
    end

    def temp_file_path
      default = File.expand_path(File.join(Dir.pwd, 'tmp'))
      return Canary.config['ScreenshotFolder'] || ENV['AUTOTEST_SAVE_PATH'] || default
    end
  end

  class StoryWithState
    attr_accessor :passed, :message, :setup_passed, :exception, :run_time
    attr_reader :story, :screenshot_path, :description, :category, :file_path, :line_number, :start_date

    def initialize(story, category, description, file_path, line_number)
      @story = story
      @category = category
      @description = description
      @screenshot_path = File.join(Canary.temp_file_path, make_valid_file_name(Canary.config['ImageExt']))
      @file_path = file_path
      @line_number = line_number
      @passed = true
      @setup_passed = true
      @message = ''
      @start_date = Time.now
      @run_time = 0
    end

    def passed?
      @passed
    end

    def failed?
      !@passed
    end

    def make_valid_file_name(ext)
      name = "#{@category}_#{@description}"
      return "#{name.gsub(/\s*['":\/]+\s*/, '_').gsub(/\s/, '-')}.#{ext}"
    end

    def stringify(arg)
      if arg.respond_to?(:to_a)
        arg.to_a
      else
        [arg.inspect]
      end
    end

    def to_hash
      hash = {
          'start_date'      => @start_date,
          'run_time'        => @run_time,
          'category'        => @category,
          'description'     => @description,
          'passed'          => @passed,
          'file_name'       => @file_path,
          'line_number'     => @line_number,
          'story_context'   => @story.story_context.to_a.map{|x|x.to_s},
          'tasks'           => @story.task_history.map { |task|
            {
                'task_context'  => task.context.to_a.map{|x|x.to_s},
                'actions'       => task.actions.map { |action|
                  {
                      'method_name'   => action.metadata[:method],
                      'arguments'     => stringify(action.metadata[:args]),
                      'wrapped_class' => action.wrapped_class.to_s,
                      'result'        => action.result.to_s,
                      'log'           => action.log
                  }
                }
            }
          }
      }
      unless @exception.nil?
        hash.merge!(
            {
                'exception'       => @exception.message,
                'backtrace'       => @exception.backtrace
            })
      end
      hash
    end

    def to_json(*a)
      self.to_hash.to_json(*a)
    end
  end

  class SetupStoryWithState < StoryWithState
    def initialize(story, category, file_path, line_number, nest_depth)
      super(story, category, 'Setup', file_path, line_number)
      @nest_depth = nest_depth
    end
  end
end

RSpec.configure do |config|
  config.include(Canary::Script)
  config.add_formatter Canary::RSpec::StoryManager
  config.add_formatter Canary::RSpec::ConsoleReporter
  config.add_formatter Canary::RSpec::ScreenshotFormatter
  config.add_formatter Canary::RSpec::MongoPersistence
end
