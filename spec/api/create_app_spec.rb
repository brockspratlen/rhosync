require File.join(File.dirname(__FILE__),'..','spec_helper')
require 'rubygems'
require 'sinatra'
require 'rack/test'
require 'spec'
require 'spec/autorun'
require 'spec/interop/test'

set :environment, :test
set :run, false

require File.join(File.dirname(__FILE__),'..','..','rhosync.rb')

describe "Rhosync" do
  include Rack::Test::Methods
  include RhosyncStore
  
  it_should_behave_like "SourceAdapterHelper"

  def app
    @app ||= Sinatra::Application
  end
  
  before(:each) do
    @appname = 'rhotestapp'
    do_post "/apps/#{@a.name}/clientlogin", "login" => @u.login, "password" => 'testpass'
  end
  
  it "should upload zipfile and create app and sources" do
    file = File.join(File.dirname(__FILE__),'..','apps',@appname)
    compress(file)
    zipfile = File.join(file,"#{@appname}.zip")
    post "/api/#{@appname}/create_app", :payload => {
      :upload_file => Rack::Test::UploadedFile.new(zipfile, "application/octet-stream"),
      :foo => 'bar'}
    FileUtils.rm zipfile
    App.is_exist?(@appname,'name').should == true
    sources = App.with_key(@appname).sources.members.sort
    sources.should == ["SampleAdapter", "SimpleAdapter"]
    sources.each do |source|    
      Source.is_exist?(source,'name').should == true
    end
    target = File.join(File.dirname(__FILE__),'..','..','apps',@appname)
    entries = Dir.entries(target)
    entries.reject! {|entry| entry == '.' || entry == '..'}
    entries.sort.should == ["config.yml", "sources", "vendor"]
    FileUtils.rm_rf File.join(File.dirname(__FILE__),'..','..','apps')
  end
  
  def compress(path)
    path.sub!(%r[/$],'')
    archive = File.join(path,File.basename(path))+'.zip'
    FileUtils.rm archive, :force=>true
    Zip::ZipFile.open(archive, 'w') do |zipfile|
      Dir["#{path}/**/**"].reject{|f|f==archive}.each do |file|
        zipfile.add(file.sub(path+'/',''),file)
      end
    end
  end
end