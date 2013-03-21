module Canary
  class TestSuite 
    attr_accessor :versions, :story_count
    def initialize(service)
      @service = service
      @versions = nil
      @start_date = Time.now
      @script_host = Socket.gethostname
      @target_env = Canary.config['TargetEnvironment']
      @passed_count = 0
      @failed_count = 0
      @ignored_count = 0
    end

    def start(count)
      @story_count = count
      @in_progress = true
      @service.save_test(to_hash)
    end

    def complete(was_cancelled=false)
      @in_progress = false
      @was_cancelled = was_cancelled
      @end_date = Time.now
      @service.save_test(to_hash)
    end

    def cancel
      complete(false)
    end

    def start_group(category, file, line, nest_depth)
      group_story = Story.new(Canary.factory_class.new)
      new_test = Canary::SetupStoryWithState.new(group_story, category, file, line, nest_depth)
      Canary.setup_story = new_test
      Canary.testing_phase = :setup
    end

    def add_new_story(category, description, file, line)
      active_story = Story.new(Canary.factory_class.new)
      new_story = Canary::StoryWithState.new(active_story, category, description, file, line)
      new_story.in_progress = true
      Canary.story_list << new_story
      Canary.testing_phase = :story
      new_story.setup_passed = Canary.setup_story.passed?
      @service.add_category
      @service.save_story(Canary.active_story)
    end

    def example_passed(message, run_time)
      close_example(message, run_time)
      @passed_count += 1
      @service.increment_passed_count
      Canary.active_story.passed = true
      @service.save_story(Canary.active_story)
      @story_id = nil
    end

    def example_failed(message, exception, run_time)
      close_example(message, run_time)
      @failed_count += 1
      @service.increment_failed_count
      Canary.active_story.passed = false
      Canary.active_story.exception = exception
      attach_screenshot(Canary.active_story)
      @service.save_story(Canary.active_story)
    end

    def to_hash
      hash = {
        'start_date' => @start_date,
        'script_host' => @script_host,
        'target_env' => @target_env,
        'story_count' => @story_count,
        'passed_count' => @passed_count,
        'failed_count' => @failed_count,
        'ignored_count' => @ignored_count,
        'in_progress' => @in_progress
      }
      hash.merge!({
              'test_name' => Canary.test_name 
            }) unless Canary.test_name.nil?
      hash.merge! ({
              'target_versions' => @versions
            }) unless @versions.nil?
      hash.merge! ({
              'was_cancelled' => @was_cancelled,
              'end_date' => @end_date
            }) unless @in_progress
      hash
    end

    private 
    def close_example(message, run_time)
      Canary.active_story.message = message
      Canary.active_story.run_time = run_time
      Canary.active_story.in_progress = false
    end 

    def attach_screenshot(test)
      if Capybara.current_driver == :poltergeist
        Capybara.page.driver.render(test.screenshot_path, :full => true)
      elsif Capybara.current_driver == :selenium
        Capybara.page.driver.browser.save_screenshot(test.screenshot_path)
      end
    end
  end

  class StoryWithState
    attr_accessor :passed, :message, :setup_passed, :exception, :run_time, :in_progress
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
      return "#{name.gsub(/\s*['":\/\?]+\s*/, '_').gsub(/\s/, '-')}.#{ext}"
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
          'in_progress'     => in_progress,
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