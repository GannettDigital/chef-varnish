class Chef
  class Resource
    # Configure Varnish logging.
    class VarnishLog < Chef::Resource::LWRPBase
      self.resource_name = :varnish_log
      actions :configure
      default_action :configure

      attribute :name, kind_of: String, name_attribute: true
      attribute :file_name, kind_of: String, default: '/var/log/varnish/varnishlog.log'
      attribute :logrotate, kind_of: [TrueClass, FalseClass], default: true
      attribute :logrotate_path, kind_of: String, default: '/etc/logrotate.d'
      attribute :pid, kind_of: String, default: '/var/run/varnishlog.pid'
      attribute :log_format, kind_of: String, default: 'varnishlog',
                             equal_to: ['varnishlog', 'varnishncsa']
      attribute :ncsa_format_string, kind_of: String,
                                     default: '%h|%l|%u|%t|\"%r\"|%s|%b|\"%{Referer}i\"|\"%{User-agent}i\"'
      attribute :instance_name, kind_of: String,
                                default: nil
    end
  end

  # varnish and varnish(log|ncsa) services sometimes enter a race
  # condition. This wrapper causes Chef to pause before restarting
  # these services, and it will rescue up to 5 times.
  module ProviderExtensions
    def restart_service
      tries ||= 5
      begin
        if @new_resource.service_name =~ /varnish(log|ncsa)/
          sleep 5
        end
        super
      rescue
        retry unless (tries -= 1).zero?
      end
    end

    def start_service
      tries ||= 5
      begin
        if @new_resource.service_name =~ /varnish(log|ncsa)/
          sleep 5
        end
        super
      rescue
        retry unless (tries -= 1).zero?
      end
    end
  end

  class Provider
    class Service
      # Add functionality to restart and start services.
      class Init
        prepend ProviderExtensions
      end
    end
  end

  class Provider
    class Service
      # Add functionality to restart and start services.
      class Systemd
        prepend ProviderExtensions
      end
    end
  end

  class Provider
    # Configure Varnish logging.
    class VarnishLog < Chef::Provider::LWRPBase
      include VarnishCookbook::Helpers

      def whyrun_supported?
        true
      end

      def action_configure
        configure_varnish_log
      end

      def configure_varnish_log
        template "/etc/default/#{new_resource.log_format}" do
          if node['platform_family'] == 'debian'
            path "/etc/default/#{new_resource.log_format}"
            source 'lib_varnishlog.erb'
          elsif node['init_package'] == 'systemd'
            path "/etc/systemd/system/#{new_resource.log_format}.params"
            source 'lib_varnishlog_systemd.erb'
          else
            path "/etc/sysconfig/#{new_resource.log_format}"
            source 'lib_varnishlog.erb'
          end
          cookbook 'varnish'
          owner 'root'
          group 'root'
          mode '0644'
          variables(
            config: new_resource,
            varnish_version: varnish_version
          )
          action :create
          notifies :restart, "service[#{new_resource.log_format}]", :delayed
        end
        if new_resource.logrotate
          template "#{new_resource.logrotate_path}/#{new_resource.log_format}" do
            source 'lib_logrotate_varnishlog.erb'
            path "#{new_resource.logrotate_path}/#{new_resource.log_format}"
            cookbook 'varnish'
            owner 'root'
            group 'root'
            mode '0644'
            variables(config: new_resource)
            action :create
            only_if { ::File.exist?(new_resource.logrotate_path) }
          end
        end
        service new_resource.log_format do
          supports restart: true, reload: true
          action %w(enable start)
        end
      end
    end
  end
end
