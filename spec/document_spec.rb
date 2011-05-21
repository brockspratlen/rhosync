require File.join(File.dirname(__FILE__),'spec_helper')
require File.join(File.dirname(__FILE__), 'support', 'shared_examples')

describe "Document" do
  it_behaves_like "SharedRhosyncHelper", :rhosync_data => true do
    before(:each) do
      @s = Source.load(@s_fields[:name],@s_params)
    end
    
    it "should generate client docname" do
      @c.docname(:foo).should == "client:#{@a.id}:#{@u.id}:#{@c.id}:#{@s_fields[:name]}:foo"
    end

    it "should generate source docname" do
      @s.docname(:foo).should == "source:#{@a.id}:#{@u.id}:#{@s_fields[:name]}:foo"
    end

    it "should flash_data for docname" do
      @c.put_data(:foo1,{'1'=>@product1})
      Store.db.keys(@c.docname('*')).should == [@c.docname(:foo1)]
      @c.flash_data('*')
      Store.db.keys(@c.docname(:foo)).should == []
    end

    it "should rename doc" do
      set_state(@c.docname(:key1) => @data)
      @c.rename(:key1,:key2)
      verify_result(@c.docname(:key1) => {}, @c.docname(:key2) => @data)
    end
  end
end