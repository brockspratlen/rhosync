module Rhosync
  class SourceSync
    attr_reader :adapter
    
    def initialize(source)
      @source = source
      raise InvalidArgumentError.new('Invalid source') if @source.nil?
      raise InvalidArgumentError.new('Invalid app for source') unless @source.app
      @adapter = SourceAdapter.create(@source)
    end
    
    # CUD Operations
    def create(client_id)
      _measure_and_process_cud('create',client_id)
    end
    
    def update(client_id)
      _measure_and_process_cud('update',client_id)
    end
    
    def delete(client_id)
      _measure_and_process_cud('delete',client_id)
    end
    
    # Pass through CUD to adapter, no data stored
    def pass_through_cud(cud_params,query_params)
      return if _auth_op('login') == false
      res,processed_objects = {},[]
      begin
        ['create','update','delete'].each do |op|
          key,objects = op,cud_params[op]
          objects.each do |key,value|
            case op
            when 'create'
              @adapter.send(op.to_sym,value)
            when 'update'
              value['id'] = key
              @adapter.send(op.to_sym,value)
            when 'delete'
              value['id'] = key
              @adapter.send(op.to_sym,value)
            end
            processed_objects << key
          end if objects
        end
      rescue Exception => e
        log "Error in pass through method: #{e.message}"
        res['error'] = {'message' => e.message } 
      end
      _auth_op('logoff')
      res['processed'] = processed_objects
      res.to_json
    end
    
    # Read Operation; params are query arguments
    def read(client_id=nil,params=nil)
      _read('query',client_id,params)
    end
    
    def search(client_id=nil,params=nil)
      return if _auth_op('login',client_id) == false
      res = _read('search',client_id,params)
      _auth_op('logoff',client_id)
      res
    end

    def process_cud(client_id)
      if @source.cud_queue or @source.queue
        async(:cud,@source.cud_queue || @source.queue,client_id)
      else
        do_cud(client_id)
      end   
    end
    
    def do_cud(client_id)
      return if _auth_op('login') == false
      self.create(client_id)
      self.update(client_id)
      self.delete(client_id)
      _auth_op('logoff')
    end
    
    def process_query(params=nil)
      if @source.query_queue or @source.queue
        async(:query,@source.query_queue || @source.queue,nil,params)
      else
        do_query(params)
      end   
    end
    
    def do_query(params=nil)
      result = nil
      @source.if_need_refresh do
        Stats::Record.update("source:query:#{@source.name}") do
          return if _auth_op('login') == false
          result = self.read(nil,params)
          _auth_op('logoff')
        end  
      end
      result
    end
    
    # Enqueue a job for the source based on job type
    def async(job_type,queue_name,client_id=nil,params=nil)
      SourceJob.queue = queue_name
      Resque.enqueue(SourceJob,job_type,@source.id,
        @source.app_id,@source.user_id,client_id,params)
    end
    
    def push_objects(objects,timeout=10,raise_on_expire=false)
      @source.lock(:md,timeout,raise_on_expire) do |s|
        doc = @source.get_data(:md)
        orig_doc_size = doc.size
        objects.each do |id,obj|
          doc[id] ||= {}
          doc[id].merge!(obj)
        end  
        diff_count = doc.size - orig_doc_size
        @source.put_data(:md,doc)
        @source.update_count(:md_size,diff_count)
      end      
    end    

    def push_deletes(objects,timeout=10,raise_on_expire=false)
      @source.lock(:md,timeout,raise_on_expire) do |s|
        doc = @source.get_data(:md)
        orig_doc_size = doc.size
        objects.each do |id|
          doc.delete(id)
        end  
        diff_count = doc.size - orig_doc_size
        @source.put_data(:md,doc)
        @source.update_count(:md_size,diff_count)
      end      
    end
    
    private
    def _auth_op(operation,client_id=-1)
      edockey = client_id == -1 ? @source.docname(:errors) :
        Client.load(client_id,{:source_name => @source.name}).docname(:search_errors)
      begin
        Store.flash_data(edockey) if operation == 'login'
        @adapter.send operation
      rescue Exception => e
        log "SourceAdapter raised #{operation} exception: #{e}"
        log e.backtrace.join("\n")
        Store.put_data(edockey,{"#{operation}-error"=>{'message'=>e.message}},true)
        return false
      end
      true
    end
    
    def _process_create(client,key,value,links,creates,deletes)
      # Perform operation
      link = @adapter.create value
      # Store object-id link for the client
      # If we have a link, store object in client document
      # Otherwise, store object for delete on client
      if link
        links ||= {}
        links[key] = { 'l' => link.to_s }
        creates ||= {}
        creates[link.to_s] = value
      else
        deletes ||= {}
        deletes[key] = value
      end
    end
    
    def _process_update(client,key,value)
      begin
        # Add id to object hash to forward to backend call
        value['id'] = key
        # Perform operation
        @adapter.update value
      rescue Exception => e
        # TODO: This will be slow!
        cd = client.get_data(:cd)
        client.put_data(:update_rollback,{key => cd[key]},true) if cd[key]
        raise e
      end
    end
    
    def _process_delete(client,key,value,dels)
      value['id'] = key
      # Perform operation
      @adapter.delete value
      dels ||= {}
      dels[key] = value
    end
    
    def _measure_and_process_cud(operation,client_id)
      Stats::Record.update("source:#{operation}:#{@source.name}") do
        _process_cud(operation,client_id)
      end
    end
    
    def _process_cud(operation,client_id)
      errors,links,deletes,creates,dels = {},{},{},{},{}
      client = Client.load(client_id,{:source_name => @source.name})
      modified = client.get_data(operation)
      # Process operation queue, one object at a time
      modified.each do |key,value|
        begin
          # Remove object from queue
          modified.delete(key)
          # Call on source adapter to process individual object
          case operation
          when 'create'
            _process_create(client,key,value,links,creates,deletes)
          when 'update'
            _process_update(client,key,value)
          when 'delete'
            _process_delete(client,key,value,dels)
          end
        rescue Exception => e
          log "SourceAdapter raised #{operation} exception: #{e}"
          log e.backtrace.join("\n")
          errors ||= {}
          errors[key] = value
          errors["#{key}-error"] = {'message'=>e.message}
          break
        end
      end
      # Record operation results
      { "delete_page" => deletes,
        "#{operation}_links" => links,
        "#{operation}_errors" => errors }.each do |doctype,value|
        client.put_data(doctype,value,true) unless value.empty?
      end
      unless operation != 'create' and creates.empty?
        client.put_data(:cd,creates,true)
        client.update_count(:cd_size,creates.size)
        @source.lock(:md) do |s| 
          s.put_data(:md,creates,true)
          s.update_count(:md_size,creates.size)
        end
      end
      if operation == 'delete'
        # Clean up deleted objects from master document and corresponding client document
        client.delete_data(:cd,dels)
        client.update_count(:cd_size,-dels.size)
        @source.lock(:md) do |s| 
          s.delete_data(:md,dels)
          s.update_count(:md_size,-dels.size)
        end
      end
      # Record rest of queue (if something in the middle failed)
      if modified.empty?
        client.flash_data(operation)
      else
        client.put_data(operation,modified)
      end
      modified.size
    end
    
    # Metadata Operation; source adapter returns json
    def _get_data(method)
      if @adapter.respond_to?(method)
        data = @adapter.send(method) 
        if data
          @source.put_value(method,data)
          @source.put_value("#{method}_sha1",Digest::SHA1.hexdigest(data))
        end
      end
    end
    
   # Read Operation; params are query arguments
    def _read(operation,client_id,params=nil)
      errordoc = nil
      result = nil
      begin
        if operation == 'search'
          client = Client.load(client_id,{:source_name => @source.name})
          errordoc = client.docname(:search_errors)
          compute_token(client.docname(:search_token))
          result = @adapter.search(params)
          @adapter.save(client.docname(:search)) unless @source.is_pass_through?
        else
          errordoc = @source.docname(:errors)
          [:metadata,:schema].each do |method|
            _get_data(method)
          end
          result = @adapter.do_query(params)
        end
        # operation,sync succeeded, remove errors
        Store.lock(errordoc) do
          Store.flash_data(errordoc)
        end
      rescue Exception => e
        # store sync,operation exceptions to be sent to all clients for this source/user
        log "SourceAdapter raised #{operation} exception: #{e}"
        log e.backtrace.join("\n")
        Store.lock(errordoc) do
          Store.put_data(errordoc,{"#{operation}-error"=>{'message'=>e.message}},true)
        end
      end
      # pass through expects result hash
      @source.is_pass_through? ? result : true
    end
  end
end
