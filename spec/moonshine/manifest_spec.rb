require 'test_helper'

module Moonshine::Iptables
end

describe Moonshine::Manifest do

  after do
    if @manifest && application_template && application_template.exist?
      application_template.delete
    end
  end

  def application_template
    @application_template ||= @manifest.rails_root.join('app', 'manifests', 'templates', 'passenger.conf.erb')
  end

  it 'should load configuration' do
    assert_not_nil Moonshine::Manifest.configuration
    assert_not_nil Moonshine::Manifest.configuration[:application]
  end

  it 'should load environment specific configuration' do
    assert_equal 'what what what', Moonshine::Manifest.configuration[:test_yaml]
  end

  context 'templates' do
    it 'should use moonshine templates by default' do
      @manifest = Moonshine::Manifest::Rails.new
      @manifest.configure(:application => 'bar')

      moonshine_template = Pathname.new(__FILE__).dirname.join('..', '..', 'lib', 'moonshine', 'manifest', 'rails', 'templates', 'passenger.vhost.erb')
      template_contents = 'moonshine template: <%= configuration[:application] %>'
      @manifest.stubs(:local_template).returns(application_template)

      assert_match 'ServerName yourapp.com', @manifest.template(moonshine_template)
    end


    it 'should allow overriding by user provided templates in app/manifests/templates' do
      @manifest = Moonshine::Manifest.new
      @manifest.configure(:application => 'bar')

      FileUtils.mkdir_p application_template.dirname
      application_template.open('w') {|f| f.write "application template: <%= configuration[:application] %>" }

      moonshine_template = Pathname.new(__FILE__).dirname.join('..', '..', 'lib', 'moonshine', 'manifest', 'rails', 'templates', 'passenger.conf.erb')
      application_template = @manifest.rails_root.join('app', 'manifests', 'templates', 'passenger.conf.erb')
      assert application_template.exist?, "#{application_template} should exist, but didn't"
      assert moonshine_template.exist?, "#{moonshine_template} should exist, but didn't"

      # should return the output from that existing thing
      assert_match 'application template: bar', @manifest.template(moonshine_template)
    end
  end

  it 'should load plugins' do
    @manifest = Moonshine::Manifest.new
    assert Moonshine::Manifest.plugin(:iptables)
    # eval is configured in test/rails_root/vendor/plugins/moonshine_eval_test/moonshine/init.rb
    assert Moonshine::Manifest.configuration[:eval]
    @manifest = Moonshine::Manifest.new
    assert @manifest.respond_to?(:foo)
    assert @manifest.class.recipes.map(&:first).include?(:foo)
  end

  it 'should load database.yml into configuration[:database]' do
    assert_not_equal nil, Moonshine::Manifest.configuration[:database]
    assert_equal 'production', Moonshine::Manifest.configuration[:database][:production]
  end

  describe '#on_stage' do
    before { @manifest = Moonshine::Manifest.new }
    context 'using a string' do
      it 'should run on_stage block when stage matches the given string' do
        @manifest.expects(:deploy_stage).returns("my_stage")

        assert_equal 'on my_stage', @manifest.on_stage("my_stage") { "on my_stage" }
      end

      it "should not call block when it doesn't match" do
        @manifest.stubs(:deploy_stage).returns("not_my_stage")

        assert_nil @manifest.on_stage("my_stage") { "on my_stage" }
      end
    end

    context 'using a symbol' do
      it 'should call block when it matches' do
        @manifest.expects(:deploy_stage).returns("my_stage")

        assert_equal 'on my_stage', @manifest.on_stage(:my_stage) { "on my_stage" }
      end

      it "should not cal block when it doesn't match" do
        @manifest.stubs(:deploy_stage).returns("not_my_stage")

        assert_nil @manifest.on_stage(:my_stage) { "on my_stage" }
      end
    end

    context 'using an array of strings' do
      it 'should call block when it matches ' do
        @manifest.stubs(:deploy_stage).returns("my_stage")
        assert_equal 'on one of my stages', @manifest.on_stage("my_stage", "my_other_stage") { "on one of my stages" }

        @manifest.expects(:deploy_stage).returns("my_other_stage")
        assert_equal 'on one of my stages', @manifest.on_stage("my_stage", "my_other_stage") { "on one of my stages" }
      end

      it "should not call block when it doesn't match" do
        @manifest.stubs(:deploy_stage).returns("not_my_stage")

        assert_nil @manifest.on_stage("my_stage", "my_other_stage") { "on one of my stages" }
      end
    end

    context 'using an array of symbols' do
      it 'should call the block it matches' do
        @manifest.stubs(:deploy_stage).returns("my_stage")

        assert_equal 'on one of my stages', @manifest.on_stage(:my_stage, :my_other_stage) { "on one of my stages" }

        @manifest.expects(:deploy_stage).returns("my_other_stage")
        assert_equal 'on one of my stages', @manifest.on_stage(:my_stage, :my_other_stage) { "on one of my stages" }
      end

      it "should not the call block when it doesn't match" do
        @manifest.stubs(:deploy_stage).returns("not_my_stage")

        assert_nil @manifest.on_stage(:my_stage, :my_other_stage) { "on one of my stages" }
      end
    end

    context 'using :unless with a string' do
      it 'should not call block when it matches' do
        @manifest.stubs(:deploy_stage).returns("my_stage")

        assert_nil @manifest.on_stage(:unless => "my_stage") { "not on one of my stages" }
      end

      it 'should call block when it does not match' do
        @manifest.stubs(:deploy_stage).returns("my_stage")

        assert_equal 'not on one of my stages', @manifest.on_stage(:unless => "not_my_stage") { "not on one of my stages" }
      end
    end

    context 'using :unless with a symbol' do
      it 'should not call block when it matches' do
        @manifest.stubs(:deploy_stage).returns("my_stage")

        assert_nil @manifest.on_stage(:unless => :my_stage) { "not on one of my stages" }
      end

      it 'should call block when it does not match' do
        @manifest.stubs(:deploy_stage).returns("my_stage")

        assert_equal 'not on one of my stages', @manifest.on_stage(:unless => :not_my_stage) { "not on one of my stages" }
      end

    end

    context 'using :unless with an array of strings' do
      it 'should not call block when it matches' do
        @manifest.stubs(:deploy_stage).returns("my_stage")
        assert_nil @manifest.on_stage(:unless => ["my_stage", "my_other_stage"]) { "not on one of my stages" }
      end

      it 'should call block when it does not match' do
        @manifest = Moonshine::Manifest.new
        @manifest.stubs(:deploy_stage).returns("not_my_stage")
        assert_equal "not on one of my stages", @manifest.on_stage(:unless => ["my_stage", "my_other_stage"]) { "not on one of my stages" }
      end
    end

    context 'using :unless with an array of symbols' do
      it 'should not call block when it matches' do
        @manifest.stubs(:deploy_stage).returns("my_stage")
        assert_nil @manifest.on_stage(:unless => [:my_stage, :my_other_stage]) { "not on one of my stages" }
      end

      it 'should call block when it does not match' do
        @manifest.stubs(:deploy_stage).returns("not_my_stage")
        assert_equal "not on one of my stages", @manifest.on_stage(:unless => [:my_stage, :my_other_stage]) { "not on one of my stages" }
      end
    end

  end

end
