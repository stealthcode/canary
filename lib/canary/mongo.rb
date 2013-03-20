module Canary
  class MongoDBService
    def initialize(host, port)
      @client = Mongo::MongoClient.new(host, port)
      @db = @client[Canary.config['MongoDbName']]
      @story_coll = @db['story']
      @test_coll = @db['test']
      @category_coll = @db['category']
      @screenshot_coll = @db['screenshot']
      @release_coll = @db['release']
      @grid = Mongo::Grid.new(@db)
    end

    def increment_passed_count
      @test_coll.update({'_id' => @test_id}, {'$inc' => {'passed_count' => 1}})
    end

    def increment_failed_count
      @test_coll.update({'_id' => @test_id}, {'$inc' => {'failed_count' => 1}})
    end

    def save_story(story)
      story_data = {}
      story_data['test_id'] = @test_id
      story_data['_id'] = @story_id if @story_id

      unless story.passed
        opts = {
            :filename => story.make_valid_file_name(Canary.config['ImageExt']),
            :content_type => Canary.config['ImageContentType'],
            :meta_data => {
                'test_id' => @test_id
            }
        }
        begin
          File.open(story.screenshot_path, 'rb') { |file|
            story_data['screenshot_id'] = @grid.put file.read, opts
          }
        rescue => e
          story_data['screenshot_exception'] = e.message
        end

      end
      @story_id = @story_coll.save story_data.merge!(story.to_hash)
    end

    def add_category
      @category_id = @category_coll.save(Canary.categories.merge({'test_id' => @test_id}))
      Canary.categories.merge!('_id' => @category_id)
    end

    def save_test(test)
      @test_id = @test_coll.save(test.to_hash)
      unless test.versions.nil?
        @release_coll.update(
          {'application' => @test_suite.versions},
          {'$set' => {'dirty' => true}, '$push' =>{'tests' => @test_id}},
          {:upsert => true})
      end
    end
  end
end