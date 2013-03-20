module Canary
  class AggregateLogger
    class StoryLogger
      def puts(msg)
        if Canary.debug_mode
          Canary.active_story.story.task_history.last.actions.last.log << {:description => "PhantomJS: #{msg}", :features => []} rescue nil
        end
      end
    end

    def puts(msg)
      loggers.each{|l|l.puts(msg)}
    end

    def add(logger)
      loggers << logger
    end
    alias :<< :add 

    def loggers
      @loggers ||= [StoryLogger.new]
    end
  end
end