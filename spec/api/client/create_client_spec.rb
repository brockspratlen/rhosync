require File.join(File.dirname(__FILE__),'..','api_helper')

describe "RhosyncApiCreateUser" do
  it_should_behave_like "ApiHelper" do  
    it "should create client for a user" do
      post "/api/client/create_client", {:api_token => @api_token, :user_id => @u_fields[:login]}
      last_response.should be_ok
      clients = User.load(@u_fields[:login]).clients.members
      clients.size.should == 2
      clients.include?(last_response.body).should == true
    end
  end
end