require 'test_helper'

class Moonshine::Manifest::ApacheTest < Test::Unit::TestCase
  def setup
    @manifest = Moonshine::Manifest::Rails.new
  end

  def test_default_configuration
    @manifest.apache_server

    apache2_conf_content = @manifest.files['/etc/apache2/apache2.conf'].content

    @manifest.configuration[:apache].should be_kind_of(Hash)

    @manifest.configuration[:apache][:keep_alive].should == 'Off'
    apache2_conf_content.should have_apache_directive('KeepAlive', 'Off')

    @manifest.configuration[:apache][:max_keep_alive_requests].should == 100
    apache2_conf_content.should have_apache_directive('MaxKeepAliveRequests', 100)

    @manifest.configuration[:apache][:keep_alive_timeout].should == 15
    apache2_conf_content.should have_apache_directive('KeepAliveTimeout', 15)

    @manifest.configuration[:apache][:max_clients].should == 150
    apache2_conf_content.should have_apache_directive('MaxClients', 150)

    @manifest.configuration[:apache][:server_limit].should == 16
    apache2_conf_content.should have_apache_directive('ServerLimit', 16)

    @manifest.configuration[:apache][:timeout].should == 300
    apache2_conf_content.should have_apache_directive('Timeout', 300)
  end

  def test_overridden_configuration_early
    @manifest.configure :apache => {
      :keep_alive => 'On',
      :max_keep_alive_requests => 200,
      :keep_alive_timeout => 30,
      :max_clients => 300,
      :server_limit => 32,
      :timeout => 600
    }
    @manifest.apache_server

    apache2_conf_content = @manifest.files['/etc/apache2/apache2.conf'].content

    @manifest.configuration[:apache][:timeout].should == 600
    apache2_conf_content.should have_apache_directive('Timeout', 600)

    @manifest.configuration[:apache][:keep_alive].should == 'On'
    apache2_conf_content.should have_apache_directive('KeepAlive', 'On')

    @manifest.configuration[:apache][:max_keep_alive_requests].should == 200
    apache2_conf_content.should have_apache_directive('MaxKeepAliveRequests', 200)

    @manifest.configuration[:apache][:keep_alive_timeout].should == 30
    apache2_conf_content.should have_apache_directive('KeepAliveTimeout', 30)

    in_apache_if_module apache2_conf_content, 'mpm_worker_module' do |mpm_worker_module|
      @manifest.configuration[:apache][:max_clients].should == 300
      mpm_worker_module.should have_apache_directive('MaxClients', 300)

      @manifest.configuration[:apache][:server_limit].should == 32
      mpm_worker_module.should have_apache_directive('ServerLimit', 32)
    end

  end

  def test_overridden_configuration_late
    @manifest.apache_server
    @manifest.configure :apache => { :keep_alive => 'On' }

    apache2_conf_content = @manifest.files['/etc/apache2/apache2.conf'].content

    @manifest.configuration[:apache][:keep_alive].should == 'On'
    apache2_conf_content.should have_apache_directive('KeepAlive', 'On')
  end

  def test_default_keepalive_off
    @manifest.apache_server

    apache2_conf_content = @manifest.files['/etc/apache2/apache2.conf'].content
    apache2_conf_content.should have_apache_directive('KeepAlive', 'Off')
  end

  def test_installs_apache
    @manifest.apache_server

    apache = @manifest.services["apache2"]
    apache.should_not == nil
    apache.require.to_s.should == @manifest.package('apache2-mpm-worker').to_s
  end

  def test_enables_mod_ssl_if_ssl
    @manifest.configure(:ssl => {
      :certificate_file => 'cert_file',
      :certificate_key_file => 'cert_key_file',
      :certificate_chain_file => 'cert_chain_file'
    })

    @manifest.apache_server

    @manifest.execs.find { |n, r| r.command == '/usr/sbin/a2enmod ssl' }.should_not == nil
  end

  def test_enables_mod_rewrite
    @manifest.apache_server

    @manifest.execs["a2enmod rewrite"].should_not == nil
  end

  def test_enables_mod_status
    @manifest.apache_server

    @manifest.execs["a2enmod status"].should_not == nil
    @manifest.files["/etc/apache2/mods-available/status.conf"].content.should match(/127.0.0.1/)
  end
end
