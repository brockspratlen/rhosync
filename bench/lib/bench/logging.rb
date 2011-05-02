module Bench
  module Logging
    def log_prefix
      # FIXME: in ruby1.8:  "%d" % nil => 0
      # but ruby1.9: TypeError: can't convert nil into Integer      
      # "[T:%03d|I:%03d]" % [@thread_id,@iteration]      
      "[T:%03d|I:%03d]" % [@thread_id.to_i, @iteration.to_i]
    end
    
    def bench_log(msg)
      Rhosync.log msg
    end
  end
end