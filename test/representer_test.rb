require "test_helper"

require "representable/json"

class RepresenterTest < MiniTest::Spec
  Album  = Struct.new(:title, :artist)
  Artist = Struct.new(:name)

  class Create < Trailblazer::Operation
    require "trailblazer/operation/representer"
    include Representer

    contract do
      property :title
      validates :title, presence: true
      property :artist, populate_if_empty: Artist do
        property :name
        validates :name, presence: true
      end
    end

    def process(params)
      @model = Album.new # NO artist!!!
      validate(params[:album], @model)
    end
  end


  # Infers representer from contract, no customization.
  class Show < Create
    def process(params)
      @model = Album.new("After The War", Artist.new("Gary Moore"))
      @contract = @model
    end
  end


  # Infers representer, adds hypermedia.
  require "roar/json/hal"
  class HypermediaCreate < Create
    representer do
      include Roar::JSON::HAL

      link(:self) { "//album/#{represented.title}" }
    end
  end

  class HypermediaShow < HypermediaCreate
    def process(params)
      @model = Album.new("After The War", Artist.new("Gary Moore"))
      @contract = @model
    end
  end


  # rendering
  # generic contract -> representer
  it do
    res, op = Show.run({})
    op.to_json.must_equal %{{"title":"After The War","artist":{"name":"Gary Moore"}}}
  end

  # contract -> representer with hypermedia
  it do
    res, op = HypermediaShow.run({})
    op.to_json.must_equal %{{"title":"After The War","artist":{"name":"Gary Moore"},"_links":{"self":{"href":"//album/After The War"}}}}
  end


  # parsing
  it do
    res, op = Create.run(album: %{{"title":"Run For Cover","artist":{"name":"Gary Moore"}}})
    op.contract.title.must_equal "Run For Cover"
    op.contract.artist.name.must_equal "Gary Moore"
  end

  it do
    res, op = HypermediaCreate.run(album: %{{"title":"After The War","artist":{"name":"Gary Moore"},"_links":{"self":{"href":"//album/After The War"}}}})
    op.contract.title.must_equal "After The War"
    op.contract.artist.name.must_equal "Gary Moore"
  end





  # explicit representer set with ::representer_class=.
  require "roar/decorator"
  class JsonApiCreate < Trailblazer::Operation
    include Representer

    contract do # we still need contract as the representer writes to the contract twin.
      property :title
    end

    class AlbumRepresenter < Roar::Decorator
      include Roar::JSON
      property :title
    end
    self.representer_class = AlbumRepresenter

    def process(params)
      @model = Album.new # NO artist!!!
      validate(params[:album], @model)
    end
  end

  class JsonApiShow < JsonApiCreate
    def process(params)
      @model = Album.new("After The War", Artist.new("Gary Moore"))
      @contract = @model
    end
  end

  # render.
  it do
    res, op = JsonApiShow.run({})
    op.to_json.must_equal %{{"title":"After The War"}}
  end

  # parse.
  it do
    res, op = JsonApiCreate.run(album: %{{"title":"Run For Cover"}})
    op.contract.title.must_equal "Run For Cover"
  end
end

class InternalRepresenterAPITest < MiniTest::Spec
  Song = Struct.new(:id)

  describe "#represented" do
    class Show < Trailblazer::Operation
      include Representer, Model
      model Song, :create

      representer do
        property :class
      end
    end

    it "uses #model as represented, per default" do
      Show.present({}).to_json.must_equal '{"class":"InternalRepresenterAPITest::Song"}'
    end

    class ShowContract < Show
      def represented
        contract
      end
    end

    it "can be overriden to use the contract" do
      ShowContract.present({}).to_json.must_equal %{{"class":"#{ShowContract.contract_class}"}}
    end
  end

  describe "#to_json" do
    class OptionsShow < Trailblazer::Operation
      include Representer

      representer do
        property :class
        property :id
      end

      def to_json(*)
        super(@params)
      end

      def model!(params)
        Song.new(1)
      end
    end

    it "allows to pass options to #to_json" do
      OptionsShow.present(include: [:id]).to_json.must_equal '{"id":1}'
    end
  end
end