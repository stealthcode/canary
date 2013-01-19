module Canary
  module Script
    def story
      Canary.active_test.story
    end

    def go_to_url(url, c = [])
      story.go_to_url(url, c)
    end

    def go_to(sym, c = [])
      story.go_to(sym, c)
    end

    def on_page?(p, c = [])
      story.on_page?(p, c)
    end

    def click(e, c = [])
      story.click(e, c)
    end

    def go_to_page(p, c = [])
      story.go_to_page(p, c)
    end

    def fill_out(arg, c = [])
      story.fill_out(arg, c)
    end

    def choose(arg, c = [])
      story.choose(arg, c)
    end

    def page(c = [])
      story.page(c)
    end

    def find(model, args = {})
      story.find(model, args)
    end

    def run_sql(model, args = {})
      story.run(model, args)
    end

    def run_job(job_name, args=[])
      story.run_job(job_name, args)
    end

    def element(element_name, context = [])
      story.find_element(element_name, context)
    end
    alias :elements :element

  end
end