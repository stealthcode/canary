require 'tiny_tds'

module Canary
  module Data
    module SQLTemplateOperation
      def execute(hash)
        hash.each{|key, value|
          token = "$$$#{key.to_s.upcase}$$$"
          raise "Token not found ''#{token}'" unless @sql.include?(token)
          @sql.gsub!(token, value.to_s)
        }
        @connection.query(@sql).each(:symbolize_keys => true)
      end
    end

    class SQLData
      include SQLTemplateOperation
      include Canary::StoryLogging

      def initialize(connection_key)
        @connection = Canary.data_connections[connection_key]
      end
    end

    class SQLMutableData
      include SQLTemplateOperation
      include Canary::StoryLogging

      def initialize(connection_key)
        @connection = Canary.data_connections[connection_key]
      end
    end

    class SQLDataConnection
      def initialize(un, pw, host)
        begin
          @client = TinyTds::Client.new(:username => un, :password => pw, :host => host)
        rescue => e
          puts "Cannot connect to host #{host}"
          raise e
        end

        at_exit do
          close
        end
      end

      def query(sql)
        @client.execute(sql)
      end

      def close
        @client.close
      end
    end
  end
end
