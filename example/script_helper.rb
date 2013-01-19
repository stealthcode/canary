$:.push File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'canary'
Canary.config_path = File.expand_path(File.dirname(__FILE__))
Dir[File.dirname(__FILE__) + '/pages/*.rb'].each {|file| require file }
Dir[File.dirname(__FILE__) + '/sql/*.rb'].each {|file| require file }
Canary.poltergeist_options = {
    :phantomjs => phantomjs_path,
    :window_size => [1280, 1024],
    :phantomjs_options => %w(--ignore-ssl-errors=yes),
    :timeout => 60
}
Canary.factory_class = PageInjector
