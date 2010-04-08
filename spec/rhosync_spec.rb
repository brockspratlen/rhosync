require File.join(File.dirname(__FILE__),'spec_helper')

describe "Rhosync" do
  it_should_behave_like "RhosyncHelper"
  it_should_behave_like "TestappHelper"
  
  it "should bootstrap Rhosync with block" do
    Rhosync.bootstrap(get_testapp_path) do |rhosync|
      rhosync.vendor_directory = 'foo'
    end
    path = get_testapp_path
    File.expand_path(Rhosync.base_directory).should == path
    File.expand_path(Rhosync.app_directory).should == path
    File.expand_path(Rhosync.data_directory).should == File.join(path,'data')
    Rhosync.vendor_directory.should == 'foo'
    Rhosync.blackberry_bulk_sync.should == false
    Rhosync.environment.should == :development  
    App.is_exist?(@test_app_name).should be_true
  end
  
  it "should bootstrap Rhosync with RHO_ENV provided" do
    ENV['RHO_ENV'] = 'production'
    Rhosync.bootstrap(get_testapp_path)
    Rhosync.environment.should == :production
    ENV.delete('RHO_ENV')
  end
  
  it "should bootstrap with existing app" do
    app = App.create(:name => @test_app_name)
    App.should_receive(:load).once.with(@test_app_name).and_return(app)
    Rhosync.bootstrap(get_testapp_path)
  end
  
  it "should configure app_name in settings.yml" do
    Rhosync.get_config(Rhosync.base_directory)[Rhosync.environment][:app_name].should == @test_app_name
  end
  
  it "should bootstrap app with no sources" do
    app = App.create(:name => @test_app_name)
    Rhosync.stub!(:get_config).and_return({Rhosync.environment.to_sym => {:app_name => @test_app_name}})
    App.should_receive(:load).twice.with(@test_app_name).and_return(app)
    Rhosync.bootstrap(get_testapp_path)
    App.load(@test_app_name).sources.members.should == []
  end
  
  it "should load subclass initializer and Rhosync::Application initializer" do
    Testapp.initializer
    Rhosync.base_directory.should == ENV['PWD']
  end
  
  class Testapp < Rhosync::Application
    def self.initializer
      super
    end
  end
end