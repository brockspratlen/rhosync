require 'uuidtools'
module Rhosync
  class ApiToken < Model
    field :value,:string
    field :user_id,:string
    validates_presence_of :user_id
    
    def self.create(fields)
      fields[:value] = fields[:value] || Rhosync.api_token || get_random_uuid
      fields[:id] = fields[:value]
      object = super(fields)
    end
    
    def user
      @user ||= User.load(self.user_id)
    end
  end
end
    