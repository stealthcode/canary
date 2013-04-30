module Canary
  module Exec
    class AbstractExec
      include Canary::StoryLogging

      def execute_job(args)

      end
    end

    class PowershellExec < AbstractExec
      def initialize(host)
        @remote_host = host || :default
        if @remote_host == :default && %w(RemoteHost RemoteCredential RemotePassword).all? {|key| Canary.config.has_key?(key)}
          @is_local = false
          @remote_host = {
          :remote_host => Canary.config['RemoteHost'],
          :username => Canary.config['RemoteCredential'],
          :password => Canary.config['RemotePassword']
          }
        elsif @remote_host.is_a?(Hash) and [:remote_host, :username, :password].all? {|key| @remote_host.has_key?(key)}
          @is_local = false
        else
          @is_local = true
        end
      end

      def setup_job(args)
        log "No setup required for #{self.class}"
      end

      def execute_job(*args)
        puts "Running #@path #{"on #@remote_host" unless @is_local}"
        run_ps (append_args @path, args)
      end

      def append_args(command, cmd_line_args)
        return command
        # commandline args are not working as a result of passing a full context to story
        cmd_line_args = [cmd_line_args] unless cmd_line_args.is_a? Array
        stringy_args = cmd_line_args.map{|e|
          e.class <= DateTime ?
              e.strftime("%Y-%m-%dT%H:%M:%S") :
              e.to_s
        }
        [command].concat(stringy_args).join(' ')
      end

      def run_ps (command)
        if @is_local || @remote_host.nil?
          ps_command = "icm -ScriptBlock {#{command}}"
        else
          ps_command = "icm #{@remote_host[:remote_host]} -ScriptBlock {#{command}} -Credential (New-Object System.Management.Automation.PsCredential(('#{@remote_host[:username]}'), (ConvertTo-SecureString '#{@remote_host[:password]}' -AsPlainText -force)))"
        end

        ps_command = "powershell -NoProfile -OutputFormat Text -InputFormat none -Command \"&{#{ps_command.gsub(/"/, '\'')}}\""
        puts "executing powershell command: #{ps_command}"
        result = `#{ps_command}`
        p result
        result
      end
    end

    class InlinePowershellCommand < PowershellExec
      def initialize(command, remote_host = :local)
        super(remote_host)
        @path = command
      end
    end
  end
end