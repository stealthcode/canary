require 'capybara/rspec'

module Canary
  module Page
    class AbstractPage
      include RSpec::Matchers
      include Canary::StoryLogging

      attr_accessor :path, :host

      public
      def initialize
        @page_elements = {}

      end

      def go_to_url(url)
        log("Open url '#{url}'")
        page.visit(url).should_not satisfy {|r| r['status'] == 'fail'}
        task.result = self
      end

      def go_to(sym)
        send("go_to_#{sym}")
      end

      def click(sym)
        perform_action :click, sym
      end

      def fill_out(sym, value)
        perform_action :set, sym, value
      end

      def perform_action(verb, noun, *args, &b)
        method_name = "#{verb}_#{noun}"
        if self.respond_to? method_name
          send(method_name, *args, &b)
        elsif @page_elements.keys.include?(noun)
          @page_elements[noun].send(verb, *args, &b)
        else
          raise "Cannot execute page behavior #{method_name} for #{self.class} "
        end
      end

      def open
        log("Navigating to page '#{self.class}'")
        go_to_url(url)
        self.should be_on_page
        task.result = self
      end

      def url
        "#@host#@path"
      end

      def on_page?
        log 'Executing the default on_page?'
        false
      end

      def set_timeout(time)
        prev_timeout = Capybara.default_wait_time
        Capybara.default_wait_time = time
        result = yield
        Capybara.default_wait_time = prev_timeout
        result 
      end

      def contains(key, selector)
        page.send("has_#{key}?", selector)
      end
      alias :contain :contains
      alias :contain? :contains
      alias :contains? :contains

      def find(*arg)
        if [:css, :xpath].include? arg[0]
          type = arg[0]
          selector = arg[1]
          opts = arg[2] || {:visible => true}
        else
          type = :css
          selector = element_name = arg[0]
          opts = arg[1]
        end

        if @page_elements.keys.include?(element_name) && @page_elements[element_name].class <= CapybaraElement
          element(element_name, opts)
        elsif selector.is_a?(Symbol)
          raise "Could not find named element #{element_name} on page #{self.class}, known elements include #{@page_elements.keys}"
        else
          Element.new("#{type} #{selector}", [{type => selector}], task).find(opts)
        end
      end

      def element(element_name, opts={})
        @page_elements[element_name]
      end
      alias :elements :element

      def all(*arg)
        if [:css, :xpath].include? arg[0]
          type = arg[0]
          selector = arg[1]
          opts = arg[2] || {:visible => true}
        else
          type = :css
          selector = element_name = arg[0]
        end

        if @page_elements.keys.include?(element_name) && @page_elements[element_name].class <= Element
          @page_elements[element_name].find(opts)
        else
          Collection.new("#{type} #{selector}", [{type => selector}], task).find(opts)
        end
      end

      def choose(selector, value)
        perform_action(:choose, selector, value)
      end

      def has_element(name, locator, klass= Element)
        unless locator.class <= Hash || locator.class <= Array && locator[0].class <= Hash
          raise "Element locator #{locator} must be a hash or array of hashes"
        end
        locator = [locator] unless locator.is_a?(Array)
        @page_elements.merge!(name => klass.new(name, locator, self))
      end

      def has_collection(name, locator)
        has_element(name, locator, Collection)
      end

      def self.where_am_i
        @@page_classes.each {|c| return test_page.class if (test_page = c.new).on_page?}
        return AbstractPage
      end

      def page
        Capybara.page
      end

    end

    class CapybaraElement
      attr_reader :locators
      def initialize(name, locators, parent)
        @name = name
        @locators = locators
        @parent = parent
      end

      def [](ind)
        element[ind]
      end


      def exists?(opts = {})
        for_any do |lookup_method, identifier|
          Capybara.page.has_selector?(lookup_method, identifier, opts)
        end
      end

      def not_visible?
        msg = "Checking if #@name is not visible."
        begin
          results = for_any do |lookup_method, identifier|
            Capybara.page.has_no_selector?(lookup_method, identifier, :visible => true)
          end
          msg = "#@name is #{results ? "not " : ""} visible."
          results
        ensure
          log msg
        end
      end
      alias :hidden? :not_visible?

      protected
      def for_any
        all_locators.each{ |method, selector|
          begin
            return true if yield(method, selector) rescue false
          end
        }
        false
      end

      def all_locators
        results = []
        @locators.each { |locator|
          locator.each{|lookup_method, selectors|
            selectors = [selectors] unless selectors.is_a? Hash
            selectors.each {|selector|
              results << [lookup_method, selector]
            }
          }
        }
        results
      end

      def element(*opts)
        last_exception = nil
        all_locators.each { |lookup_method, identifier|
          begin
            return lookup(lookup_method, identifier, opts)
          rescue Capybara::ElementNotFound => e
            last_exception = e
            next
          end
        }
        raise last_exception
      end

      def method_missing(method, *args, &block)
        locator_options = {}
        unless args.nil?
          args.select{|e| is_an_option(e)}.each {|hash|
            locator_options.merge! hash
          }
          method_args = args.reject{|e| is_an_option(e) }
        end

        msg = ""
        step = "Locating element(s) for #@name"
        begin
          search_result = element(locator_options)
          msg = "#@name##{method}(#{method_args.join(', ')})"
          step = "Running"
          call_result = search_result.send(method, *method_args, &block)
          msg = "#{msg} returned #{call_result.inspect}"
          step = "ran successfully"
          call_result
        ensure
          log("#{msg} #{step}")
        end
      end

      def log(msg, features = [])
        @parent.task << {:description => msg, :features => features}
      end

      def is_an_option(e)
        e.is_a? Hash and (e.keys.include?(:visible) or e.keys.include?(:text))
      end

    end

    class Element < CapybaraElement
      def lookup(lookup_method, identifier, opts)
        Capybara.page.find(lookup_method, identifier, opts)
      end
    end

    class Collection < CapybaraElement
      def lookup(lookup_method, identifier, opts)
        Capybara.page.all(lookup_method, identifier, opts)
      end
    end
  end
end