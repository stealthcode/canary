require_relative '../lib/canary/story'

class PageInjector
  def inject(instance)

  end
end
module Canary
  class << self
    attr_accessor :active_page
  end

  class PageTask
    def == (other)
      self.class == other.class &&
          self.context == other.context &&
          self.actions == other.actions &&
          self.wrapped_class == other.wrapped_class
    end

  end

  class TaskResult
    def == (other)
      self.metadata[:method] == other.metadata[:method]
    end
  end
end

class TestPage < Canary::Page::AbstractPage
  attr_accessor :task
  def initialize
    self.stub(:open) { self }
  end

  def open
    return self
  end

  def get_true
    true
  end

end

describe Canary::Story do
  before(:all) {
    Canary.active_page = Canary::Page::AbstractPage
  }
  let(:injector) { PageInjector.new }
  let(:context) { [] }
  before { @story = Canary::Story.new(injector) }
  subject { @story }

  context :task_history do
    subject {@story.task_history}
    it {should have(0).tasks}
    context :page do
      before {@story.page}
      it {should have(1).page_task}
      it {should include(Canary::PageTask.new(injector, context))}
    end

    context 'when running go_to_page' do
      before {@story.go_to_page TestPage}
      it {should have(1).page_task}
      it {
        valid_page_task = Canary::PageTask.new(injector, context)
        valid_page_task.actions << Canary::TaskResult.new({:method => :open, :args => []}, Canary::Page::AbstractPage)
        should include(valid_page_task)
      }
    end
  end

end

describe Canary::PageTask do
  let(:context) { [] }
  before {
    @injector = double('PageInjector', :inject => true)
    @task = Canary::PageTask.new(@injector, context)
  }
  subject { @task }

  context 'initialized' do
    its(:actions) {should have(0).actions}
    its(:context) {should have(context.length).elements}
  end

  context :save_results do
    let(:result) { TestPage.new }
    before {
      Canary.active_page = Canary::Page::AbstractPage
      @task_result = double('TaskResult')
      @task_result.should_receive(:result=).once.with(kind_of(TestPage))
      @task.save_results(result, @task_result)
    }
    it 'should set the Canary.active_page to the result class' do
      Canary.active_page.should == TestPage
    end
  end

  context :task_subject do
    before {
      Canary.active_page = TestPage
      @task_result = double('TaskResult', :wrapped_class= => true)
      @task_result.should_receive(:wrapped_class=).once.with(TestPage)
      @injector.should_receive(:inject).once.with(kind_of(TestPage))
    }
    subject {@task.task_subject(@task_result)}
    its(:class) {should <= TestPage}
  end

  context 'non-chainable PageTask' do
    before {
      Canary.active_page = TestPage
      @task.chainable = false
      @injector.should_receive(:inject).once.with(kind_of(TestPage))

    }
    subject {@task.get_true}
    it {should be_true}

  end

  context 'chainable PageTask' do
    before {
      Canary.active_page = TestPage
      @task.chainable = true
      @result = @task.get_true
    }
    it 'should return the task' do
      @result.should == @task
    end
  end

end