require 'active_support/concern'

module Mongoid
  module Symbolize
    extend ActiveSupport::Concern

    # Symbolize Mongoid attributes. Add:
    #   symbolize :attr_name
    # to your model class, to make an attribute return symbols instead of
    # string values. Setting such an attribute will accept symbols as well
    # as strings.
    #
    # There's no need for 'field :attr_name', symbolize will do it.
    #
    # Example:
    #   class User
    #     include Mongoid::Document
    #     symbolize :gender, :in => [:female, :male]
    #     symbolize :so, :in => {
    #       :linux   => "Linux",
    #       :mac     => "Mac OS X"
    #     }
    #     symbolize :gui, , :in => [:gnome, :kde, :xfce], :allow_blank => true
    #     symbolize :browser, :in => [:firefox, :opera], :i18n => false
    #   end
    #
    # It will automattically lookup for i18n:
    #
    # models:
    #   symbolizes:
    #     user:
    #       gender:
    #         female: Girl
    #         male: Boy
    #
    # You can skip i18n lookup with :i18n => false
    #   symbolize :gender, :in => [:female, :male], :i18n => false
    #
    # Its possible to use boolean fields also.
    #   symbolize :switch, :in => [true, false]
    #
    #   ...
    #     switch:
    #       "true": On
    #       "false": Off
    #       "nil": Unknown
    #
    module ClassMethods
      # Specifies that values of the given attributes should be returned
      # as symbols. The table column should be created of type string.

      def symbolize *attr_names
        configuration = {}
        configuration.update(attr_names.extract_options!)

        enum = configuration[:in] || configuration[:within]
        i18n = configuration.delete(:i18n)
        i18n = (!enum.instance_of?(Hash) && enum) if i18n.nl?
        scopes      = configuration.delete :scopes
        methods     = configuration.delete :methods
        capitalize  = configuration.delete :capitalize
        validation  = configuration.delete(:validate) != false
        field_type  = configuration.delete :type
        default_opt = configuration.delete :default
        enum = [true, false] if field_type == Boolean

        unless enum.nil?

          attr_names.each do |attr_name|
            # attr_name = attr_name.to_s

            #
            # Builds Mongoid 'field :name, type: type, :default'
            #
            mongo_opts  = ", :type => #{field_type || 'Symbol'}"
            mongo_opts += ", :default => :#{default_opt}" if default_opt
            class_eval("field :#{attr_name} #{mongo_opts}")

            const =  "#{attr_name}_values"
            if enum.is_a?(Hash)
              values = enum
            else
              values = {}
              enum.map do |val|
                key = val.respond_to?(:to_sym) ? val.to_sym : val
                values[key] = capitalize ? val.to_s.capitalize : val.to_s
              end
            end

            # Get the values of :in
            const_set const.upcase, values unless const_defined? const.upcase
            ev = if i18n
                   # This one is a dropdown helper
                   code =  "#{const.upcase}.map { |k,v| [I18n.t(\"mongoid.symbolizes.\#{ActiveSupport::Inflector.underscore(self.model_name)}.#{attr_name}.\#{k}\"), k] }" #.to_sym rescue nila
                   "def self.get_#{const}; #{code}; end;"
                 else
                   "def self.get_#{const}; #{const.upcase}.map(&:reverse); end"
                 end
            class_eval(ev)

            if methods
              values.each do |value|
                define_method("#{value[0]}?") do
                  self.send(attr_name) == value[0]
                end
              end
            end

            if scopes
              values.each do |value|
                if value[0].respond_to?(:to_sym)
                  scope value[0].to_sym, where({ attr_name => value[0].to_sym })
                end
              end
            end

            if validation
              validation = "validates :#{attr_names.join(', :')}"
              validation += ", :inclusion => { :in => #{values.keys.inspect} }"
              validation += ", :allow_nil => true" if configuration[:allow_nil]
              validation += ", :allow_blank => true" if configuration[:allow_blank]
              class_eval validation
            end
          end
        end

        #
        # Creates <attribute>_text helper, human text for attribute.
        #
        attr_names.each do |attr_name|
          if i18n # memoize call to translate... good idea?
            define_method "#{attr_name}_text" do
              attr = read_attribute(attr_name)
              return nil if attr.nil?
              I18n.t("mongoid.symbolizes.#{self.class.model_name.underscore}.#{attr_name}.#{attr}")
            end
          elsif enum
            class_eval("def #{attr_name}_text; #{attr_name.to_s.upcase}_VALUES[#{attr_name}]; end")
          else
            class_eval("def #{attr_name}_text; #{attr_name}.to_s; end")
          end
        end

      end

    end # ClassMethods
  end # Symbolize
end # Mongoid

# Symbolize::Mongoid = Mongoid::Symbolize
