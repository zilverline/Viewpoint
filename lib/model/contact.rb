#############################################################################
# Copyright © 2010 Dan Wanek <dan.wanek@gmail.com>
#
#
# This file is part of Viewpoint.
# 
# Viewpoint is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as published
# by the Free Software Foundation, either version 3 of the License, or (at
# your option) any later version.
# 
# Viewpoint is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
# Public License for more details.
# 
# You should have received a copy of the GNU General Public License along
# with Viewpoint.  If not, see <http://www.gnu.org/licenses/>.
#############################################################################

module Viewpoint
  module EWS
    # Represents a Contact Item in the Exchange datastore.
    class Contact < Item

      # This is a class method that creates a new Contact in the Exchange Data Store.
      # @param [Hash] item A Hash of values based on values found here:
      #   http://msdn.microsoft.com/en-us/library/aa581315.aspx
      # @param [String, Symbol] folder_id The folder to create this item in. Either a
      #   DistinguishedFolderId (must me a Symbol) or a FolderId (String)
      # @param [String] send_invites "SendToNone/SendOnlyToAll/SendToAllAndSaveCopy"
      #   See:  http://msdn.microsoft.com/en-us/library/aa565209.aspx
      # @example Typical Usage
      #   item = {
      #     :file_as => {:text => 'Dan Wanek'},
      #     :given_name => {:text => 'Dan Wanek'},
      #     :company_name => {:text => 'Test Company'},
      #     :email_addresses => [
      #       {:entry => {:key => 'EmailAddress1', :text => 'myemail@work.com'}},
      #       {:entry => {:key => 'EmailAddress2', :text => 'myemail@home.com'}}
      #     ],
      #     :physical_addresses => [
      #       {:entry => {:key => 'Business', :sub_elements => {:street => {:text => '6343 N Baltimore'}, :city => {:text => 'Bismarck'}, :state => {:text => 'ND'} }}}
      #     ],
      #     :phone_numbers => [
      #       {:entry => {:key => 'BusinessPhone', :text => '7012220000'}}
      #     ],
      #     :job_title => {:text => 'Systems Architect'}
      #   }
      # @example Minimal Usage
      def self.create_item_from_hash(item, folder_id = :contacts)
        conn = Viewpoint::EWS::EWS.instance
        resp = conn.ews.create_contact_item(folder_id, item)
        if(resp.status == 'Success')
          resp = resp.items.shift
          self.new(resp[resp.keys.first])
        else
          raise EwsError, "Could not create Contact. #{resp.code}: #{resp.message}"
        end
      end

      # Create a Contact in the Exchange Data Store
      def self.add_contact()
        item = {}
        
        conn = Viewpoint::EWS::EWS.instance
        resp = conn.ews.create_contact_item()

        if(resp.status == 'Success')
          resp = resp.items.shift
          self.new(resp[resp.keys.first])
        else
          raise EwsError, "Could not add contact. #{resp.code}: #{resp.message}"
        end
      end

      # Initialize an Exchange Web Services item of type Contact
      def initialize(ews_item)
        super(ews_item)
      end
      
      def set_email_addresses(email1, email2=nil, email3=nil)
        changes = []
        type = self.class.name.split(/::/).last.ruby_case.to_sym
        k = :email_addresses
        v = 'EmailAddress1'
        changes << {:set_item_field => 
          [{:indexed_field_uRI => {:field_uRI => FIELD_URIS[k][:text], :field_index => v}}, {type=>{k => {:entry => {:key => v, :text => email1}}}}]} unless email1.nil?
        v = 'EmailAddress2'
        changes << {:set_item_field => 
          [{:indexed_field_uRI => {:field_uRI => FIELD_URIS[k][:text], :field_index => v}}, {type=>{k => {:entry => {:key => v, :text => email2}}}}]} unless email2.nil?
        v = 'EmailAddress3'
        changes << {:set_item_field => 
          [{:indexed_field_uRI => {:field_uRI => FIELD_URIS[k][:text], :field_index => v}}, {type=>{k => {:entry => {:key => v, :text => email3}}}}]} unless email3.nil?
        @updates.merge!({:preformatted => changes}) {|k,v1,v2| v1 + v2}
      end


      private

      def init_methods
        super()

        define_str_var :file_as, :file_as_mapping, :display_name, :job_title, :given_name, :surname, :company_name
        define_attr_str_var :complete_name, :first_name, :middle_name, :last_name, :initials, :full_name
        define_inet_addresses :email_addresses, :im_addresses
        define_phone_numbers :phone_numbers
        define_physical_addresses :physical_addresses
      end

            
      # Define email_addresses or im_addresses for a Contact
      def define_inet_addresses(*inet_addresses)
        inet_addresses.each do |itype|
          eval "@#{itype} ||= {}"
          return unless self.instance_variable_get("@#{itype}").empty?
          if(@ews_item.has_key?(itype))
            @ews_methods << itype
            if(@ews_item[itype][:entry].is_a?(Array))
              @ews_item[itype][:entry].each do |entry|
                next if entry.keys.length == 1
                eval "@#{itype}[entry[:key].ruby_case.to_sym] = (entry.has_key?(:text) ? entry[:text] : '')"
              end
            else
              entry = @ews_item[itype][:entry]
              next if entry.keys.length == 1
              eval "@#{itype}[entry[:key].ruby_case.to_sym] = (entry.has_key?(:text) ? entry[:text] : '')"
            end
            self.instance_eval <<-EOF
          def #{itype}
            self.instance_variable_get "@#{itype}"
          end
          EOF
          else
            @ews_methods_undef << itype
          end
        end
      end
      
      def define_phone_numbers(phone_numbers)
        @phone_numbers ||= {}
        return unless @phone_numbers.empty?
        if(@ews_item.has_key?(phone_numbers))
          if(@ews_item[phone_numbers][:entry].is_a?(Array))
            @ews_item[phone_numbers][:entry].each do |entry|
              next if entry.keys.length == 1
              @phone_numbers[entry[:key].ruby_case.to_sym] = (entry.has_key?(:text) ? entry[:text] : "")
            end
          else # it is a Hash then
            entry = @ews_item[phone_numbers][:entry]
            return if entry.keys.length == 1
            @phone_numbers[entry[:key].ruby_case.to_sym] = (entry.has_key?(:text) ? entry[:text] : "")
          end
          self.instance_eval <<-EOF
          def #{phone_numbers}
            @phone_numbers
          end
          EOF
          @ews_methods << phone_numbers
        else
          @ews_methods_undef << itype
        end
      end

      # Define physical_addresses for a Contact
      def define_physical_addresses(physical_addresses)
        @physical_addresses ||= {}
        return unless @physical_addresses.empty?
        if(@ews_item.has_key?(physical_addresses))
          @ews_methods << physical_addresses
          @ews_item[physical_addresses][:entry].each do |entry|
            next if entry.keys.length == 1
            key = entry.delete(:key)
            @physical_addresses[key.ruby_case.to_sym] = {}
            entry.each_pair do |ekey,ev|
              @physical_addresses[key.ruby_case.to_sym][ekey] = ev[:text]
            end
          end
          self.instance_eval <<-EOF
          def #{physical_addresses}
            @physical_addresses
          end
          EOF
        else
          @ews_methods_undef << itype
        end
      end

    end # Contact
  end # EWS
end # Viewpoint
