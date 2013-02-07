module MemberPortal

  class PublicPage < AbstractPage
    def initialize
      super
      self.extend OnPage
      @host = Canary.config['URLs']['PublicPortal']
    end

  end

  class MemberPage < AbstractPage
    def initialize
      super
      self.extend OnPage
      @host = Canary.config['URLs']['MemberPortal']
    end
  end

  module OnPage
    def on_page?
      log("Checking if on the #{self.class} page.")
      log("Current URL: #{page.current_host}#{page.current_path}")
      page.current_path.upcase.include? @path.upcase && page.current_host.upcase == @host.upcase
    end
  end

  module Header
    def self.extended(base)
      base.has_element :nav_home, {:css => '#nav #home'}
      base.has_element :nav_my_account, {:css => '#nav #my_account'}
      base.has_element :logout, {:css => '#logout_button'}
    end
  end

  class DashboardPage < MemberPage
    def initialize
      super
      @path = '/dashboard'
      self.extend Example::MemberHeader
      has_element :welcome_message, {:css => 'div#page_banner div.welcome span'}
    end
  end

  class PageNotFoundPage < PublicPage
    def initialize
      super
      @path = '/404'
      self.extend Example::MemberHeader
      has_element :error_message, {:css => '.error'}
    end
  end

  class LoginPage < PublicPage
    def initialize
      super
      @path = '/login'
      self.extend Example::MemberHeader
      has_element :username, {:css => 'input#username'}
      has_element :password, {:css => 'input#password'}
      has_element :login, {:css => 'button#submit'}
    end

  end


end