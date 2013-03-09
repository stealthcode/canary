module Canary
  def run(spec, name, examples)
    # need to set the test name here instead of in the custom formatter
    RSpec::Core::Runner.run(spec, ['-e'] << examples)
  end
end