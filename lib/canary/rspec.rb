require 'rspec/core/formatters/base_formatter'
require 'uri'
require 'net/http'
require 'socket'
require 'mongo'
require_relative 'exec'
require_relative 'script'

module Canary::RSpec
  class StoryManager < ::RSpec::Core::Formatters::BaseFormatter
    def example_group_started(eg)
      group_story = Canary::new_story
      category = eg.metadata[:description]
      file = eg.metadata[:file_path]
      line = eg.metadata[:line_number]
      nest_depth = nested_level(eg.metadata[:example_group], 0)
      new_test = Canary::SetupStoryWithState.new(group_story, category, file, line, nest_depth)
      Canary.setup_story = new_test
      Canary.testing_phase = :setup
    end

    def example_started(example)
      super
      category_id = Canary.add_category(example)

      add_new_story(
          category_id,
          example.metadata[:description],
          example.metadata[:file_path],
          example.metadata[:line_number])
    end

    def add_new_story(category, description, file, line)
      active_story = Canary::new_story
      new_test = Canary::StoryWithState.new(active_story, category, description, file, line)
      Canary.test_suite << new_test
      Canary.testing_phase = :story
      new_test.setup_passed = Canary.setup_story.passed?
    end

    def example_passed(example)
      super(example)
      Canary.active_test.message = example.metadata[:execution_result][:status]
      Canary.active_test.run_time = example.metadata[:execution_result][:run_time]
    end

    def example_failed(example)
      super(example)
      Canary.active_test.message = example.metadata[:execution_result][:exception].message
      Canary.active_test.exception = example.metadata[:execution_result][:exception]
      Canary.active_test.run_time = example.metadata[:execution_result][:run_time]
      Canary.active_test.passed = false
    end

    private
    def nested_level(metadata, lvl)
      if metadata.has_key?(:example_group)
        lvl = nested_level(metadata[:example_group], lvl + 1)
      end
      lvl
    end
  end

  class ConsoleReporter < ::RSpec::Core::Formatters::BaseFormatter

    def initialize(args)
      super
      @last_category_id = -1
    end

    def example_passed(example)
      super
      print_category(example)
      puts " P (#{Canary.active_test.description}) -> #{Canary.active_test.message}"
    end

    def print_category(example)
      if @last_category_id != Canary.active_test.category
        puts "#{Canary.list_of_nested_groups(example).join(' < ')}"
        @last_category_id = Canary.active_test.category
      end
    end

    def example_failed(example)
      super
      print_category(example)
      puts " F (#{Canary.active_test.description}) -> #{Canary.active_test.message}"
    end

    def stop
      failing_tests = Canary.test_suite.map { |test| test if test.failed? }.select { |t| !t.nil?}
      puts "Failures: #{failing_tests.count}" if failing_tests.count > 0
      puts "Failing Tests" if failing_tests.count > 0
      print_test(failing_tests)
    end

    def print_test(failing_tests)
      story_features = Set.new
      failing_tests.each { |test|
        story = test.story
        puts "failing story         #{test.category} (#{test.description})"
        i = 1
        story.task_history.each {|step|
          step.actions.each {|action|
            msg  = "  task # #{i}             #{action.metadata[:method]} "
            msg += "#{action.metadata[:args]}" if action.metadata[:args].count > 0
            puts msg
            i += 1
            action.log.each {|step|
              action_features = step[:features].to_a.map {|f| "<#{f}>"}.join ', '
              puts "                       #{step[:description]} #{action_features}"
              story_features.merge(step[:features])
            }
          }
        }
        puts "  failure message      #{test.message}"
        puts "  all features(s)      #{story_features.to_a.map {|f| "<#{f}>"}.join ', '}"
      }
    end
  end

  class ScreenshotFormatter < ::RSpec::Core::Formatters::BaseFormatter

    def example_failed(example)
      super(example)
      if Capybara.current_driver == :poltergeist
        Capybara.page.driver.render(Canary.active_test.screenshot_path, :full => true)
      elsif Capybara.current_driver == :selenium
        Capybara.page.driver.browser.save_screenshot(Canary.active_test.screenshot_path)
      end
    end
  end

  class MongoPersistence < ::RSpec::Core::Formatters::BaseFormatter
    def initialize(output)
      super(output)
      @passed_count = 0
      @failed_count = 0
    end

    def start(count)
      setup_mongo
      @test_count = count
      @test_record = {
          'start_date' => Time.now,
          'script_host' => Socket.gethostname,
          'target_env' => Canary.config['TargetEnvironment'],
          'story_count' => @test_count,
          'in_progress' => true,
      }
      if Canary.config['CaptureVersion']
        versions = find_system_versions
        @test_record.merge! ({'target_versions' => versions})
        @test_id = @test_coll.insert(@test_record)
        @release_coll.update(
            {'application' => versions},
            {'$set' => {'dirty' => true},
             '$push' =>{'tests' => @test_id}},
            {:upsert => true})
      else
        @test_id = @test_coll.insert(@test_record)
      end

      # Catches the process when it is ended prematurely and calls #stop
      # This does not work running on windows when using the RubyMine process runner
      # see http://youtrack.jetbrains.com/issue/RUBY-11492
      at_exit { stop }
    end

    def setup_mongo
      @client = Mongo::MongoClient.new(Canary.config['MongoDbHost'], Canary.config['MongoDbPort'])
      @db = @client[Canary.config['MongoDbName']]
      @story_coll = @db['story']
      @test_coll = @db['test']
      @category_coll = @db['category']
      @screenshot_coll = @db['screenshot']
      @release_coll = @db['release']
      @grid = Mongo::Grid.new(@db)
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

    def stop
      if @finished.nil?
        @finished = true
        was_cancelled = (@test_count != @passed_count + @failed_count)
        @test_record.merge!(
            {
                'passed_count' => @passed_count,
                'failed_count' => @failed_count,
                'ignored_count' => 0,
                'in_progress' => false,
                'was_cancelled' => was_cancelled,
                'end_date' => Time.now
            })
        @test_coll.save(@test_record)
      end
    end

    def example_started(example)
      super(example)
      raise 'Cannot use the key "test_id" as an example group description' if Canary.categories.has_key?('test_id')
      @category_id = @category_coll.save(Canary.categories.merge({'test_id' => @test_id}))
      Canary.categories.merge!('_id' => @category_id)
    end

    def example_passed(example)
      super(example)
      @passed_count += 1
      persist(Canary.active_test)
    end

    def example_failed(example)
      super(example)
      @failed_count += 1
      @test_coll.save(@test_record.merge!({}))
      persist(Canary.active_test)
    end

    def persist(story)
      story_data = {}
      story_data['test_id'] = @test_id

      unless story.passed
        opts = {
            :filename => story.make_valid_file_name(Canary.config['ImageExt']),
            :content_type => Canary.config['ImageContentType'],
            :meta_data => {
                'test_id' => @test_id
            }
        }
        begin
          File.open(story.screenshot_path, 'rb') { |file|
            story_data['screenshot_id'] = @grid.put file.read, opts
          }
        rescue => e
          story_data['screenshot_exception'] = e.message
        end

      end
      @story_coll.insert story_data.merge!(story.to_hash)
      #puts story_data
    end
  end
end
