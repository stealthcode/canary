module Canary
  class TaskResult
    attr_accessor :log, :result, :metadata, :wrapped_class

    def initialize(metadata, wrapped_class)
      @log = []
      @result = nil
      @metadata = metadata
      @wrapped_class = wrapped_class
    end

    def features
      all_features = Set.new
      @log.each{|log| all_features.merge(log[:features].flatten)}
      all_features
    end

    def <<(hash)
      log << hash
    end
  end

  module StoryLogging
    def task=(task)
      @current_task = task
    end

    def task
      active_task
    end

    protected
    def log(description, features = [])
      active_task << {:description => description, :features => features}
    end

    private
    def active_task
      if @current_task.nil?
        @current_task = Canary.active_test.story.task_history.last.actions.last
      else
        @current_task
      end
    end
  end
end