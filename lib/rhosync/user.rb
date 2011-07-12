require 'digest/sha1'

module Rhosync
  # Inspired by sinatra-authentication
  # Password uses simple sha1 digest for hashing
  class User < Model
    field :login,:string
    field :email,:string
    field :salt,:string
    field :hashed_password,:string
    set   :clients, :string
    field :admin, :int
    field :token_id, :string
        
    class << self
      def create(fields={})
        raise ArgumentError.new("Reserved user id #{fields[:login]}") if fields[:login] && fields[:login] == '__shared__'
        fields[:id] = fields[:login]      
        if Rhosync.stats
          Rhosync::Stats::Record.set('users') { Store.incr('user:count') }
        else
          Store.incr('user:count')
        end
        super(fields)
      end
    
      def authenticate(login,password)
        return unless is_exist?(login)
        current_user = load(login)
        return if current_user.nil?
        return current_user if User.encrypt(password, current_user.salt) == current_user.hashed_password
      end
    end
    
    def new_password=(pass)
      self.password=(pass)
    end
    
    def password=(pass)
      @password = pass
      self.salt = User.random_string(10) if !self.salt
      self.hashed_password = User.encrypt(@password, self.salt)
    end
    
    def delete
      clients.members.each do |client_id|
        Client.load(client_id,{:source_name => '*'}).delete
      end
      self.token.delete if self.token
      if Rhosync.stats
        Rhosync::Stats::Record.set('users') { Store.decr('user:count') }
      else
        Store.decr('user:count')
      end
      super
    end
    
    def create_token
      if self.token_id && ApiToken.is_exist?(self.token_id)
        self.token.delete 
      end
      self.token_id = ApiToken.create(:user_id => self.login).id
    end
    
    def token
      ApiToken.load(self.token_id)
    end
    
    def token=(value)
      if self.token_id && ApiToken.is_exist?(self.token_id)
        self.token.delete 
      end
      self.token_id = ApiToken.create(:user_id => self.login, :value => value).id
    end
    
    def update(fields)
      fields.each do |key,value|
        self.send("#{key.to_sym}=", value) unless key == 'login'
      end  
    end
      
    protected
    def self.encrypt(pass, salt)
      Digest::SHA1.hexdigest(pass+salt)
    end

    def self.random_string(len)
      chars = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a
      newpass = ""
      1.upto(len) { |i| newpass << chars[rand(chars.size-1)] }
      return newpass
    end
  end
end