module Rhosync
  
  class StoreLockException < RuntimeError; end
  
  class Store
    RESERVED_ATTRIB_NAMES = ["attrib_type", "id"] unless defined? RESERVED_ATTRIB_NAMES
    @@db = nil
    
    class << self
      def db; @@db || @@db = _get_redis end
      
      def db=(server=nil)
        @@db = _get_redis(server)
      end
      
      def create(server=nil)
        @@db ||= _get_redis(server)
        raise "Error connecting to Redis store." unless @@db and 
          (@@db.is_a?(Redis) or @@db.is_a?(Redis::Client))
      end
  
      # Adds set with given data, replaces existing set
      # if it exists or appends data to the existing set
      # if append flag set to true
      def put_data(dockey,data={},append=false)
        if dockey and data
          flash_data(dockey) unless append
          # Inserts a hash or array
          if data.is_a?(Hash)
            @@db.pipelined do
              data.each do |key,value|
                value.each do |attrib,value|
                  unless _is_reserved?(attrib,value)
                    @@db.sadd(dockey,setelement(key,attrib,value))
                  end
                end
              end
            end
          else
            @@db.pipelined do
              data.each do |value|
                @@db.sadd(dockey,value)
              end
            end
          end
        end
        true
      end
      
      # updates objects for a given doctype, source, user
      # create new objects if necessary
      def update_objects(dockey, data={})
        return 0 unless dockey and data
        
        new_object_count = 0
        doc = get_data(dockey)
        @@db.pipelined do
          data.each do |key,value|
            is_create = doc[key].nil?
            new_object_count += 1 if is_create
            value.each do |attrib,value|
              next if _is_reserved?(attrib, value)
              
              new_element = setelement(key,attrib,value)
              element_exists = is_create ? false : doc[key].has_key?(attrib)
              if element_exists
                existing_element = setelement(key,attrib,doc[key][attrib])
                if existing_element != new_element
                  @@db.srem(dockey, existing_element)
                  @@db.sadd(dockey, new_element)
                end
              else
                @@db.sadd(dockey, new_element)
              end
            end
          end
        end
        new_object_count
      end
      
      # Removes objects from a given doctype,source,user
      def delete_objects(dockey,data=[])
        return 0 unless dockey and data
        
        deleted_object_count = 0
        doc = get_data(dockey)
        @@db.pipelined do
          data.each do |id|
            if doc[id]
              doc[id].each do |name,value|
                @@db.srem(dockey, setelement(id,name,value))
              end
              deleted_object_count += 1
            end
            doc.delete(id)
          end
        end
        deleted_object_count
      end
      
      # Adds a simple key/value pair
      def put_value(dockey,value)
        if dockey
          if value
            @@db.set(dockey,value.to_s)
          else
            @@db.del(dockey)
          end
        end
      end
    
      # Retrieves value for a given key
      def get_value(dockey)
        @@db.get(dockey) if dockey
      end
      
      def incr(dockey)
        @@db.incr(dockey)
      end
      
      def decr(dockey)
        @@db.decr(dockey)
      end
  
      # Retrieves set for given dockey,source,user
      def get_data(dockey,type=Hash)
        res = type == Hash ? {} : []
        if dockey
          members = @@db.smembers(dockey)
          members.each do |element|
            if type == Hash
              key,attrib,value = getelement(element)
              res[key] = {} unless res[key]
              res[key].merge!({attrib => value})
            else
              res << element
            end
          end if members
          res
        end
      end
  
      # Retrieves diff data hash between two sets
      def get_diff_data(src_dockey,dst_dockey,p_size=nil)
        res = {}
        if src_dockey and dst_dockey
          @@db.sdiff(dst_dockey,src_dockey).each do |element|
            key,attrib,value = getelement(element)
            res[key] = {} unless res[key]
            res[key].merge!({attrib => value})
          end
        end
        if p_size
          diff = {}
          page_size = p_size
          res.each do |key,item|
            diff[key] = item
            page_size -= 1
            break if page_size <= 0         
          end
          [diff,res.size]
        else  
          [res,res.size]
        end
      end

      # Deletes data from a given doctype,source,user
      def delete_data(dockey,data={})
        if dockey and data
          @@db.pipelined do
            data.each do |key,value|
              value.each do |attrib,val|
                @@db.srem(dockey,setelement(key,attrib,val))
              end
            end
          end
        end
        true
      end
    
      # Deletes all keys matching a given mask
      def flash_data(keymask)
        @@db.keys(keymask).each do |key|
          @@db.del(key)
        end
      end
    
      # Returns array of keys matching a given keymask
      def get_keys(keymask)
        @@db.keys(keymask)
      end
    
      # Returns true if given item is a member of the given set
      def ismember?(setkey,item)
        @@db.sismember(setkey,item)
      end
      
      # Lock a given key and release when provided block is finished
      def lock(dockey,timeout=0,raise_on_expire=false)
        m_lock = get_lock(dockey,timeout,raise_on_expire)
        res = yield
        release_lock(dockey,m_lock,raise_on_expire)
        res
      end
      
      def get_lock(dockey,timeout=0,raise_on_expire=false)
        lock_key = _lock_key(dockey)
        current_time = Time.now.to_i   
        ts = current_time+(Rhosync.lock_duration || timeout)+1
        loop do 
          if not @@db.setnx(lock_key,ts)
            current_lock = @@db.get(lock_key)
            # ensure lock wasn't released between the setnx and get calls
            if current_lock
             	current_lock_timeout = current_lock.to_i
             	if raise_on_expire or Rhosync.raise_on_expired_lock
             	  if current_lock_timeout <= current_time
             	    # lock expired before operation which set it up completed
             	    # this process cannot continue without corrupting locked data 
             	    raise StoreLockException, "Lock \"#{lock_key}\" expired before it was released"
             	  end
             	else  
             	  if current_lock_timeout <= current_time and 
             	    @@db.getset(lock_key,ts).to_i <= current_time
             	    # previous lock expired and we replaced it with our own
             	    break
             	  end
           	  end
         	  # lock was released between setnx and get - try to acquire it again
       	    elsif @@db.setnx(lock_key,ts)
         	    break
     	      end
            sleep(1)
            current_time = Time.now.to_i
          else
            break #no lock was set, so we set ours and leaving
          end
        end
        return ts
      end
      
      # Due to redis bug #140, setnx always returns true so this doesn't work
      # def get_lock(dockey,timeout=0)
      #   lock_key = _lock_key(dockey)
      #   until @@db.setnx(lock_key,1) do 
      #     sleep(1) 
      #   end
      #   @@db.expire(lock_key,timeout+1)
      #   Time.now.to_i+timeout+1
      # end
      
      def release_lock(dockey,lock,raise_on_expire=false)
        @@db.del(_lock_key(dockey)) if raise_on_expire or Rhosync.raise_on_expired_lock or (lock >= Time.now.to_i)
      end
      
      # Create a copy of srckey in dstkey
      def clone(srckey,dstkey)
        @@db.sdiffstore(dstkey,srckey,'')
      end
      
      # Rename srckey to dstkey
      def rename(srckey,dstkey)
        @@db.rename(srckey,dstkey) if @@db.exists(srckey)
      end
      
      alias_method :set_value, :put_value
      alias_method :set_data, :put_data
      
      private
      def _get_redis(server=nil)
        if ENV[REDIS_URL]
          Redis.connect(:url => ENV[REDIS_URL])
        elsif server and server.is_a?(String)
          host,port,db,password = server.split(':')
          Redis.new(:thread_safe => true, :host => host,
            :port => port, :db => db, :password => password)
        elsif server and server.is_a?(Redis)
          server
        else
          Redis.new(:thread_safe => true)
        end
      end
      
      def _lock_key(dockey)
        "lock:#{dockey}"
      end
          
      def _is_reserved?(attrib,value) #:nodoc:
        RESERVED_ATTRIB_NAMES.include? attrib
      end
    end
  end
end  