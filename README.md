# CANARY
Canary aims to provide a flexible framework for writing systems tests for web applications. 

- QA, Analysts, Devs, and Management can easily understand the test results
- Devs can get a log of context test context for easy debugging
- Scripting Devs can leverage reusable business behavior with ease

## Using the Framework
Canary requires a special fork of Poltergeist which is not hosted as a rubygem. This complicates the setup process. First git clone Canary and create an environment variable `CANARY_PATH = <canary_repo_path>/lib`
Modify your `script_helper.rb` to include the following lines of code.

```ruby
$:.push File.expand_path(ENV['CANARY_PATH'])
require 'canary'
```

### Configuration
Canary uses two a yaml configuration files during initialization. You can configure the path where the configuration files are located from your `script_helper.rb` with the following.

```ruby
Canary.config_path = File.expand_path(File.dirname(__FILE__))
```

The `config.yaml` file can contain multiple variations of config settings. The configuration set used is determined by the following order of precedence.

1. `ENV['COMPUTERNAME']`
2. `ENV['USERNAME']`
3. `'local'`

Example configuration files can be found in the `examples` directory. 

### Page Objects
Scripts can interact with pages via making calls to page objects through the Story object. The `script.rb` file includes helper methods for use in your specs. The Capybara Node object is made accessible by using the method `find(element_name_or_selector)`, `element(element_name)`, or `elements(collection_name)`. All method calls to the object returned by these methods are logged and made available in the test reports. 

### Data Objects
Database queries should be a subclass of `Canary::Data::SQLData`.

## Assumptions
- Tests are currently written using RSpec.
- Web automation uses Capybara.
- Supports PhantomJS with Poltergeist.
- Remote command execution uses Powershell v2 Invoke-Command.
- Data access performed using MS SQL.
- Test results stored in MongoDB. Requires independent installation.
- Reports hosted using NodeJS web server. Requires independent installation.

