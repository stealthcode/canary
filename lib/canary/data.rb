require 'tiny_tds'
require 'win32ole'

module Canary
  module Data
    module SQLTemplateOperation
      def execute(hash)
        hash.each{ |key, value|
          token = "$$$#{key.to_s.upcase}$$$"
          raise "Token not found ''#{token}'" unless @sql.include?(token)
          @sql.gsub!(token, value.to_s)
        }
        @connection.query(@sql)
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

    class TDSSQLDataConnection
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

    class ADOSQLDataConnection

      def initialize(connection_string)
        @client = WIN32OLE.new('ADODB.Connection')
        @client.Open(connection_string)
      end

      def self.connection(un, pw, host)
        connection_string =  "Provider=SQLOLEDB.1;"
        connection_string << "Persist Security Info=False;"
        connection_string << "User ID=#{un};"
        connection_string << "password=#{pw};"
        connection_string << "Initial Catalog=master;"
        connection_string << "Data Source=#{host};"
        connection_string << "Network Library=dbmssocn"
      end

      def query(sql)
        recordset = WIN32OLE.new('ADODB.Recordset')
        begin
          recordset.Open(sql, @client)
        rescue
          close and raise
        end
        fields = []
        recordset.Fields.each do |field|
          fields << field.Name
        end
        begin
          # Move to the first record/row, if any exist
          recordset.MoveFirst
          # Grab all records
          data = recordset.GetRows
        rescue
          data = []
        end

        results = []
        data.transpose.map{ |datarow|
          Hash[fields.zip(datarow)]
        }
      end

      def close
        @client.Close
      end

    end

  end
end
