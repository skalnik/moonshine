require 'test_helper'

# mock out the gem source index to fake like passenger is installed, but
# nothing else
module Gem  #:nodoc:
  class SourceIndex  #:nodoc:
    alias_method :orig_search, :search
    def search(gem_pattern, platform_only = false)
      if gem_pattern.name.to_s =~ /passenger/
        orig_search(gem_pattern, platform_only)
      else
        []
      end
    end
  end
end

describe Moonshine::Manifest::Rails do

  before do
    @manifest = subject
  end

  it { should be_executable }

  context "default_stack" do
    it "should support mysql" do
      @manifest.expects(:database_environment).at_least_once.returns({:adapter => 'mysql'})

      @manifest.default_stack

      @manifest.should use_recipe(:apache_server)
      @manifest.should use_recipe(:passenger_gem)
      @manifest.should use_recipe(:passenger_configure_gem_path)
      @manifest.should use_recipe(:passenger_apache_module)
      @manifest.should use_recipe(:passenger_site)

      @manifest.should use_recipe(:mysql_server)
      @manifest.should use_recipe(:mysql_gem)
      @manifest.should use_recipe(:mysql_database)
      @manifest.should use_recipe(:mysql_user)
      @manifest.should use_recipe(:mysql_fixup_debian_start)

      @manifest.should use_recipe(:rails_rake_environment)
      @manifest.should use_recipe(:rails_gems)
      @manifest.should use_recipe(:rails_directories)
      @manifest.should use_recipe(:rails_bootstrap)
      @manifest.should use_recipe(:rails_migrations)
      @manifest.should use_recipe(:rails_logrotate)

      @manifest.should use_recipe(:ntp)
      @manifest.should use_recipe(:time_zone)
      @manifest.should use_recipe(:postfix)
      @manifest.should use_recipe(:cron_packages)
      @manifest.should use_recipe(:motd)
      @manifest.should use_recipe(:security_updates)

    end

    def test_default_stack_with_postgresql
      @manifest.expects(:database_environment).at_least_once.returns({:adapter => 'postgresql' })

      @manifest.default_stack

      [:postgresql_server, :postgresql_gem, :postgresql_user, :postgresql_database].each do |pgsql_stack|
        assert @manifest.recipes.map(&:first).include?(pgsql_stack), pgsql_stack.to_s
      end
    end

    def test_default_stack_with_sqlite
      @manifest.expects(:database_environment).at_least_once.returns({:adapter => 'sqlite' })

      @manifest.default_stack

      assert @manifest.recipes.map(&:first).include?(:sqlite3), 'sqlite3'
    end
  end

  def test_automatic_security_updates
    @manifest.configure(:unattended_upgrade => { :package_blacklist => ['foo', 'bar', 'widget']})
    @manifest.configure(:user => 'rails')

    @manifest.security_updates

    assert_not_nil @manifest.packages["unattended-upgrades"]
    assert_not_nil @manifest.files["/etc/apt/apt.conf.d/10periodic"]
    assert_not_nil @manifest.files["/etc/apt/apt.conf.d/50unattended-upgrades"]
    assert_match /APT::Periodic::Unattended-Upgrade "1"/, @manifest.files["/etc/apt/apt.conf.d/10periodic"].params[:content].value
    assert_match /Unattended-Upgrade::Mail "rails@localhost";/, @manifest.files["/etc/apt/apt.conf.d/50unattended-upgrades"].params[:content].value
    assert_match /"foo";/, @manifest.files["/etc/apt/apt.conf.d/50unattended-upgrades"].params[:content].value
  end

  describe "#rails_gems" do
    it "configures gem sources" do
      @manifest.rails_gems
      assert_match /gems.github.com/, @manifest.files["/etc/gemrc"].content
    end

    it "loads gems from config" do
      @manifest.configure(:gems => [ { :name => 'jnewland-pulse', :source => 'http://gems.github.com' } ])
      @manifest.rails_gems
      assert_not_nil Moonshine::Manifest::Rails.configuration[:gems]
      Moonshine::Manifest::Rails.configuration[:gems].each do |gem|
        assert_not_nil gem_resource = @manifest.packages[gem[:name]]
        assert_equal :gem, gem_resource.provider
      end
      assert_nil @manifest.packages['jnewland-pulse'].source

    end

    it "magically loads gem dependencies" do
      @manifest.configure(:gems => [
        { :name => 'webrat' },
        { :name => 'thoughtbot-paperclip', :source => 'http://gems.github.com' }
      ])
      @manifest.rails_gems
      assert_not_nil @manifest.packages['webrat']
      assert_not_nil @manifest.packages['thoughtbot-paperclip']
      assert_not_nil @manifest.packages['libxml2-dev']
      assert_not_nil @manifest.packages['imagemagick']
    end

  end

  it "cretes directories" do
    config = {
      :application => 'foo',
      :user => 'foo',
      :deploy_to => '/srv/foo'
    }
    @manifest.configure(config)

    @manifest.rails_directories

    assert_not_nil shared_dir = @manifest.files["/srv/foo/shared"]
    assert_equal :directory, shared_dir.ensure
    assert_equal 'foo', shared_dir.owner
    assert_equal 'foo', shared_dir.group
  end

  describe "passenger" do
    def test_installs_passenger_gem
      @manifest.configure(:passenger => { :version => nil })

      @manifest.passenger_configure_gem_path
      @manifest.passenger_gem

      assert_not_nil @manifest.packages["passenger"]
      assert_equal :latest, @manifest.packages["passenger"].ensure
      end

    def test_can_pin_passenger_to_a_specific_version
      @manifest.configure(:passenger => { :version => '2.2.2' })
      @manifest.passenger_configure_gem_path
      @manifest.passenger_gem
      assert_not_nil @manifest.packages["passenger"]
      assert_equal '2.2.2', @manifest.packages["passenger"].ensure
      end

    def test_installs_passenger_module
      @manifest.passenger_configure_gem_path
      @manifest.passenger_apache_module

      assert_not_nil @manifest.packages['apache2-threaded-dev']
      assert_not_nil @manifest.files['/etc/apache2/mods-available/passenger.load']
      assert_not_nil @manifest.files['/etc/apache2/mods-available/passenger.conf']
      assert_match /PassengerUseGlobalQueue On/, @manifest.files['/etc/apache2/mods-available/passenger.conf'].content
      assert_not_nil @manifest.execs.find { |n, r| r.command == '/usr/sbin/a2enmod passenger' }
      assert_not_nil @manifest.execs.find { |n, r| r.command == '/usr/bin/ruby -S rake clean apache2' }
    end

    def test_setting_passenger_booleans_to_false
      @manifest.configure(:passenger => { :use_global_queue => false })
      @manifest.passenger_configure_gem_path
      @manifest.passenger_apache_module
      assert_match /PassengerUseGlobalQueue Off/, @manifest.files['/etc/apache2/mods-available/passenger.conf'].content
    end


    describe "passenger_site" do
      def test_configures_passenger_vhost
        @manifest.passenger_configure_gem_path
        @manifest.passenger_site

        assert_not_nil @manifest.files["/etc/apache2/sites-available/#{@manifest.configuration[:application]}"]
        assert_match /RailsAllowModRewrite On/, @manifest.files["/etc/apache2/sites-available/#{@manifest.configuration[:application]}"].content
        assert_not_nil @manifest.execs.find { |n, r| r.command == '/usr/sbin/a2dissite 000-default' }
        assert_not_nil @manifest.execs.find { |n, r| r.command == "/usr/sbin/a2ensite #{@manifest.configuration[:application]}" }
      end

      def test_passenger_vhost_configuration
        @manifest.passenger_configure_gem_path
        @manifest.configure(:passenger => { :rails_base_uri => '/test' })

        @manifest.passenger_site

        assert_match /RailsBaseURI \/test/, @manifest.files["/etc/apache2/sites-available/#{@manifest.configuration[:application]}"].content
      end

    end

    def test_ssl_vhost_configuration
      @manifest.passenger_configure_gem_path
      @manifest.configure(:ssl => {
        :certificate_file => 'cert_file',
        :certificate_key_file => 'cert_key_file',
        :certificate_chain_file => 'cert_chain_file'
      })

      @manifest.passenger_site

      assert_match /SSLEngine on/, @manifest.files["/etc/apache2/sites-available/#{@manifest.configuration[:application]}"].content
      assert_match /https/, @manifest.files["/etc/apache2/sites-available/#{@manifest.configuration[:application]}"].content
    end
    def test_vhost_basic_auth_configuration
      @manifest.passenger_configure_gem_path
      @manifest.configure(:apache => {
        :users => {
        :jimbo  => 'motorcycle',
        :joebob => 'jimbo'
      }
      })

      @manifest.passenger_site

      assert_match /<Location \/ >/, @manifest.files["/etc/apache2/sites-available/#{@manifest.configuration[:application]}"].content
      assert_match /authuserfile #{@manifest.configuration[:deploy_to]}\/shared\/config\/htpasswd/, @manifest.files["/etc/apache2/sites-available/#{@manifest.configuration[:application]}"].content
      assert_match /require valid-user/, @manifest.files["/etc/apache2/sites-available/#{@manifest.configuration[:application]}"].content
    end

    def test_vhost_allow_configuration
      @manifest.passenger_configure_gem_path
      @manifest.configure(:apache => {
        :users => {},
        :deny  => {},
        :allow => ['192.168.1','env=safari_user']
      })

      @manifest.passenger_site

      vhost = @manifest.files["/etc/apache2/sites-available/#{@manifest.configuration[:application]}"].content
      assert_match /<Location \/ >/, vhost
      assert_match /allow from 192.168.1/, vhost
      assert_match /allow from env=safari_user/, vhost
    end

    def test_vhost_deny_configuration
      @manifest.passenger_configure_gem_path
      @manifest.configure(:apache => {
        :users => {},
        :allow => {},
        :deny => ['192.168.1','env=safari_user']
      })

      @manifest.passenger_site

      assert_match /<Location \/ >/, @manifest.files["/etc/apache2/sites-available/#{@manifest.configuration[:application]}"].content
      assert_match /deny from 192.168.1/, @manifest.files["/etc/apache2/sites-available/#{@manifest.configuration[:application]}"].content
    end

  end
  
  describe "apache server" do
    it "generates htpasswd" do
      @manifest.passenger_configure_gem_path
      @manifest.configure(:apache => {
        :users => {
          :jimbo  => 'motorcycle',
          :joebob => 'jimbo'
        }
      })
      @manifest.apache_server
      
      assert_not_nil @manifest.execs.find { |n, r| r.command == 'htpasswd -b /srv/foo/shared/config/htpasswd jimbo motorcycle' }
      assert_not_nil @manifest.execs.find { |n, r| r.command == 'htpasswd -b /srv/foo/shared/config/htpasswd joebob jimbo' }
      @manifest.should have_file("#{@manifest.configuration[:deploy_to]}/shared/config/htpasswd")
    end
  end


  def test_installs_postfix
    @manifest.postfix

    @manifest.should have_package("postfix")
  end

  def test_installs_ntp
    @manifest.ntp

    @manifest.should have_service("ntp")
    @manifest.should have_package("ntp")
  end

  def test_installs_cron
    @manifest.cron_packages

    @manifest.should have_service("cron")
    @manifest.should have_package("cron")
  end

  describe "#time_zone" do
    it "sets default time zone" do
      #pending "seemed to not being run previously, due to being overridden"
      @manifest.time_zone

      @manifest.should have_file("/etc/timezone").with_content("UTC\n")
      @manifest.should have_file("/etc/localtime").symlinked_to('/usr/share/zoneinfo/UTC')
    end

    it "sets default timezone" do
      @manifest.configure(:time_zone => nil)

      @manifest.time_zone

      @manifest.should have_file("/etc/timezone").with_content("UTC\n")
      @manifest.should have_file("/etc/localtime").symlinked_to('/usr/share/zoneinfo/UTC')
    end

    it "sets configured time zone" do
      @manifest.configure(:time_zone => 'America/New_York')

      @manifest.time_zone

      @manifest.should have_file("/etc/timezone").with_content("America/New_York\n")
      @manifest.should have_file("/etc/localtime").symlinked_to('/usr/share/zoneinfo/America/New_York')
    end
  end

  describe "#log_rotate" do
    it "generates configuration files" do
      @manifest.send(:logrotate, '/srv/theapp/shared/logs/*.log', {:options => %w(daily missingok compress delaycompress sharedscripts), :postrotate => 'touch /home/deploy/app/current/tmp/restart.txt'})
      @manifest.send(:logrotate, '/srv/otherapp/shared/logs/*.log', {:options => %w(daily missingok nocompress delaycompress sharedscripts), :postrotate => 'touch /home/deploy/app/current/tmp/restart.txt'})

      @manifest.should have_package("logrotate")

      @manifest.should have_file("/etc/logrotate.d/srvtheappsharedlogslog.conf").with_content(/compress/)
      @manifest.should have_file("/etc/logrotate.d/srvotherappsharedlogslog.conf").with_content(/nocompress/)
    end

    it "is configurable" do
      @manifest.configure(
        :deploy_to => '/srv/foo',
        :rails_logrotate => {
          :options => %w(foo bar baz),
          :postrotate => 'do something'
        }
      )

      @manifest.send(:rails_logrotate)

      @manifest.should have_package("logrotate")
      @manifest.should have_file("/etc/logrotate.d/srvfoosharedloglog.conf")
      
      logrotate_conf = @manifest.files["/etc/logrotate.d/srvfoosharedloglog.conf"].content

      logrotate_conf.should match(/foo/)
      logrotate_conf.should_not match(/compress/)
      logrotate_conf.should_not match(/restart\.txt/)
    end
  end

  def test_postgresql_server
    @manifest.postgresql_server

    @manifest.should have_service("postgresql-8.3")
    @manifest.should have_package("postgresql-client")
    @manifest.should have_package("postgresql-contrib")
    @manifest.should have_file("/etc/postgresql/8.3/main/pg_hba.conf")
    @manifest.should have_file("/etc/postgresql/8.3/main/postgresql.conf")
  end

  def test_postgresql_gem
    @manifest.postgresql_gem

    @manifest.should have_package("postgres")
    @manifest.should have_package("pg")
    @manifest.should have_package("postgresql-client")
    @manifest.should have_package("postgresql-contrib")
    @manifest.should have_package("libpq-dev")
  end

  def test_postgresql_database_and_user
    @manifest.expects(:database_environment).at_least_once.returns({
      :username => 'pg_username',
      :database => 'pg_database',
      :password => 'pg_password'
    })

    @manifest.postgresql_user
    @manifest.postgresql_database

    assert_not_nil @manifest.execs.find { |n, r| r.command == '/usr/bin/psql -c "CREATE USER pg_username WITH PASSWORD \'pg_password\'"' }
    assert_not_nil @manifest.execs.find { |n, r| r.command == '/usr/bin/createdb -O pg_username pg_database' }
  end

end
