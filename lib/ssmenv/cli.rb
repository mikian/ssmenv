require 'aws-sdk-ssm'
require 'thor'
require 'dotenv/parser'

module Ssmenv
  class Cli < Thor
    class_option :namespace, desc: '',
                 default: '/application'
    class_option :app, desc: 'Application name',
                 default: File.basename(Dir.pwd)
    class_option :environment, desc: 'Environment to set settings',
                 default: ENV.fetch('RAILS_ENV', 'development')
    class_option :path, desc: 'Full path to fetch environment'
    class_option :env_file, desc: 'Environment file to use', default: '.env.local'

    desc 'pull', 'Pull configuration from SSM to .env.local'
    def pull
      File.open(options.env_file, 'w') do |f|
        parameters.each do |key, value|
          f.puts "#{key}=\"#{value.gsub("\n", '\n')}\""
        end
      end
    end

    desc 'push', 'Push settings from env_File to SSM'
    def push
      secrets = Dotenv::Parser.call(File.read(options.env_file))

      secrets.each do |name, value|
        next if parameters[name] == value

        resp = client.put_parameter(name: "#{path}/#{name}", value: value, type: 'SecureString', overwrite: true)
        say "Updated #{name}: v#{resp.version}"
      end
      
    end

    no_commands do
      def path
        options.path ||= [options.namespace, options.app, options.environment].join('/')
      end

      def client
        @client ||= Aws::SSM::Client.new
      end

      def parameters
        @parameters ||= fetch_parameters.to_h
      end

      def fetch_parameters(token: nil)
        response = client.get_parameters_by_path(
          path: path,
          recursive: true,
          with_decryption: true,
          next_token: token
        )

        result = []
        result += response.parameters.map do |param|
          [param.name.gsub("#{path}/", ''), param.value]
        end

        result += fetch_parameters(token: response.next_token) if response.next_token

        result
      end

    end
  end
end
