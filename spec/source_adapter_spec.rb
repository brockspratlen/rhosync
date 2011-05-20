require File.join(File.dirname(__FILE__),'spec_helper')

class Rhosync::SourceAdapter 
  def inject_result(result) 
    @result = result
  end
  
  def inject_tmpdoc(docname)
    @tmp_docname = docname
    @stash_size = 0
  end
end

describe "SourceAdapter" do
  it_should_behave_like "SpecBootstrapHelper"
  it_should_behave_like "SourceAdapterHelper"
  
  before(:each) do
    @s = Source.load(@s_fields[:name],@s_params)
    @s.name = 'SimpleAdapter'
    @sa = SourceAdapter.create(@s,nil)
  end
  
  it "should create SourceAdapter with source" do
    @sa.class.name.should == @s.name
  end
  
  it "should create and execute SubAdapter that extends BaseAdapter" do
    @s.name = 'SubAdapter'
    @sa = SourceAdapter.create(@s,nil)
    @sa.class.name.should == 'SubAdapter'
    expected = {'1'=>@product1,'2'=>@product2}
    @sa.inject_result expected
    @sa.query.should == expected
  end
  
  it "should fail to create SourceAdapter" do
    @s_fields[:name] = 'Broken'
    broken_source = Source.create(@s_fields,@s_params)
    lambda { SourceAdapter.create(broken_source) }.should raise_error(Exception)
    broken_source.delete
  end
  
  it "should create SourceAdapter with trailing spaces" do
    @s.name = 'SimpleAdapter '
    SourceAdapter.create(@s,nil).is_a?(SimpleAdapter).should be_true
  end
    
  describe "SourceAdapter methods" do
    it "should execute SourceAdapter login method with source vars" do
      @sa.login.should == true
    end

    it "should execute SourceAdapter query method" do
      expected = {'1'=>@product1,'2'=>@product2}
      @sa.inject_result expected
      @sa.query.should == expected
    end
    
    it "should execute SourceAdapter search method and modify params" do
      params = {:hello => 'world'}
      expected = {'1'=>@product1,'2'=>@product2}
      @sa.inject_result expected
      @sa.search(params).should == expected
      params.should == {:hello => 'world', :foo => 'bar'}
    end
    
    it "should execute SourceAdapter login with current_user" do
      @sa.should_receive(:current_user).with(no_args()).and_return(@u)
      @sa.login
    end
    
    it "should execute SourceAdapter sync method" do
      expected = {'1'=>@product1,'2'=>@product2}
      @sa.inject_result expected
      @sa.do_query
      Store.get_data(@s.docname(:md)).should == expected
      Store.get_value(@s.docname(:md_size)).to_i.should == 2
    end
    
    it "should fail gracefully if @result is missing" do
      @sa.inject_result nil
      lambda { @sa.query }.should_not raise_error
    end
        
    it "should reset count if @result is empty" do
      @sa.inject_result({'1'=>@product1,'2'=>@product2})
      @sa.do_query
      Store.get_value(@s.docname(:md_size)).to_i.should == 2
      @sa.inject_result({})
      @sa.do_query
      Store.get_value(@s.docname(:md_size)).to_i.should == 0
    end
    
    it "should execute SourceAdapter create method" do
      @sa.create(@product4).should == 'obj4'
    end
    
    it "should stash @result in store and set it to nil" do
      expected = {'1'=>@product1,'2'=>@product2}
      @sa.inject_result(expected)
      @sa.inject_tmpdoc('tmpdoc')
      @sa.stash_result
      Store.get_data('tmpdoc').should == expected
    end
    
    describe "SourceAdapter metadata method" do
      
      it "should execute SourceAdapter metadata method" do
        mock_metadata_method([SimpleAdapter]) do
          @sa.metadata.should == "{\"foo\":\"bar\"}"
        end
      end
    end
  end
end