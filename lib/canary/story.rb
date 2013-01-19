require 'set'
require_relative 'task'
require_relative 'page'
require_relative 'data'

module Canary
  class Story
    attr_reader :task_history, :story_context

    def initialize(factory)
      @task_history = []
      @story_context = Set.new
      @page_factory = factory
    end

    def context=(value)
      @page_factory.set_parameters(value) unless @page_factory.nil?
    end

    def go_to(sym, context = [])
      chainable_page_task(context).go_to(sym)
    end

    def go_to_url(url, context = [])
      chainable_page_task(context).go_to_url(url)
    end

    def go_to_page(page, c = [])
      Canary.active_page = page
      chainable_page_task(c).open
    end

    def click(sym, context = [])
      chainable_page_task(context).click(sym)
    end

    def fill_out(model, context = [])
      task = chainable_page_task(context)
      model.each { |field, value|
        task.fill_out(field, value)
      }
    end

    def choose(model, context = [])
      task = chainable_page_task(context)
      model.each { |field, value|
        task.choose(field, value)
      }
    end

    def page(context = [])
      disposable_page_task(context)
    end

    def on_page?(asserted_page, context = [])
      last_page = Canary.active_page
      Canary.active_page = asserted_page
      begin
        on_new_page = disposable_page_task(context).on_page?
      ensure
        Canary.active_page = last_page unless on_new_page
      end
      on_new_page
    end

    def find_element(element_name, context = [])
      disposable_page_task(context).find(element_name)
    end
    alias :find_collection :find_element

    def find(model_class, args = {})
      query_task(model_class).execute(args)
    end

    def run(model_class, args = {})
      command_task(model_class).execute(args)
    end

    def run_job(job_class, args)
      job_task(job_class).setup_job(args)
      job_task(job_class).execute_job(args)
    end

    protected
    def query_task(model)
      @task_history << DataQueryTask.new(model)
      @task_history.last
    end

    def command_task(model)
      @task_history << DataCommandTask.new(model)
      @task_history.last
    end

    def job_task(model)
      @task_history << JobTask.new(model)
      @task_history.last
    end

    def chainable_page_task(context = [], chainable=true)
      @story_context.merge(context)
      @task_history << PageTask.new(@page_factory, context, chainable)
      @task_history.last
    end

    def disposable_page_task(context = [])
      chainable_page_task(context, false)
    end
  end

  class Task
    attr_reader :context, :actions, :wrapped_class

    def initialize(wrapped_class)
      @context = Set.new
      @actions = []
      @wrapped_class = wrapped_class
    end

    def class_of(subject, super_class)
      it = subject
      it = subject.class unless subject.is_a?(Class)
      return subject if it <= super_class
      raise "Argument should be an instance of a subclass or a subclass of #{super_class}"
    end
  end

  module DelegateAndReturn
    protected
    def method_missing(method, *args, &block)
      @actions << Canary::TaskResult.new({:method => method, :args => args}, @wrapped_class)
      instance = @wrapped_class.new
      instance.task = @actions.last
      instance.send(method, *args, &block)
    end
  end

  module DelegateAndReturnWithLogging
    protected
    def method_missing(method, *args, &block)
      @actions << Canary::TaskResult.new({:method => method, :args => args}, @wrapped_class)
      instance = @wrapped_class.new(nil)
      instance.task = @actions.last
      instance.send(method, *args, &block)
    end
  end

  class PageTask < Task
    attr_accessor :chainable

    def initialize(page_factory, context, chainable = true)
      super(Canary::Page::AbstractPage)
      @context = context.to_set
      @page_factory = page_factory
      @chainable = chainable
    end


    def add_context(context)
      @context.merge context.flatten.to_set
      self
    end

    def return_results
      @actions.last.result
    end

    def task_subject(action)
      instance = Canary.active_page.new
      instance.task = action
      @page_factory.inject(instance)
      action.wrapped_class = instance.class
      instance
    end

    def save_results(result, action)
      result_class = result.is_a?(Class) ? result : result.class
      Canary.active_page = result_class if result_class <= Canary::Page::AbstractPage
      action.result = result
    end

    protected
    def method_missing(method, *args, &block)
      @actions << action = Canary::TaskResult.new({:method => method, :args => args}, Canary::Page::AbstractPage)
      delegation_result = task_subject(action).send(method, *args, &block)
      result = save_results(delegation_result, action)
      return self if @chainable
      result
    end
  end

  class DataQueryTask < Task
    include DelegateAndReturn

    def initialize(model_class)
      super(class_of(model_class, Canary::Data::SQLData))
    end
  end

  class DataCommandTask < Task
    include DelegateAndReturn

    def initialize(model_class)
      super(class_of(model_class, Canary::Data::SQLMutableData))
    end
  end

  class JobTask < Task
    include DelegateAndReturnWithLogging

    def initialize(model_class)
      super(class_of(model_class, Canary::Exec::AbstractExec))
    end
  end

  class StoryContext < Hash
    def initialize(factory)
      @page_factory = factory
    end

    def []=(key, value)
      super
      @page_factory.set_parameters(key => value) unless @page_factory.nil?
    end
  end
end

