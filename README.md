# Temporalis

Trees with time-travel capabilities. See [post](https://github.com/markiz/historical-trees-matchup/blob/master/historic_trees.md) for the rationale behind this gem.
This one implements the node closures pattern.

Depends on `activerecord` and `activerecord-import` gems.

Should be compatible with Rails 4 and 5. Should work with sqlite3, postgres and mysql.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'temporalis'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install temporalis

## Usage

Given models `Node` and `NodeClosure`, do something like this:

```ruby
require "temporalis"

class Node < ActiveRecord::Base
  include Temporalis::ActiveRecord
  temporalis_tree closure_class: NodeClosure, use_unprefixed_aliases: true
end

t = Time.current
Node.add_node(t - 3.seconds, 100, nil)
Node.add_node(t - 2.seconds, 100, 101)
Node.add_node(t - 1.second, 102, 101)

Node.descendants(t - 2.seconds, 100) # [101]
Node.descendants(t - 1.second, 100) # [101, 102]
```

### Available methods

All the methods are always available in prefixed versions (`temporalis_add_node`), aliases without prefix are created for convenience.

* `Node.add_node(timestamp, key, parent_key)` — adds a node to the tree
* `Node.batch_add_nodes(timestamp, tuples)` — adds multiple nodes to the tree (tuples are `[key, parent_key]`, and expected to be sorted reasonably, so that you don't add a child before its parent); uses one batch query for insertion instead of multiple smaller ones
* `Node.implode_node(timestamp, key)` — "implodes" a node (removes it from tree, attaches all children to the parent)
* `Node.change_parent(timestamp, key, new_parent_key)` — moves a node
* `Node.ancestors(timestamp, key)` — list of ancestor **keys**, from bottom to top
* `Node.descendants(timestamp, key)` — list of descendant **keys**, unordered
* `Node.active_at(timestamp)` — scope of nodes active at timestamp
* `NodeClosure.active_at(timestamp)`, `NodeClosure.ancestors_of(key)`, `NodeClosure.descendants_of(key)` — closure scopes that you probably shouldn't use

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/chloeandisabel/temporalis.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## TODO

-[x] automatic testing
-[ ] rails generators
-[ ] docs

## Wrong kind of temporalis

![wrong kind of temporalis](doc/temporalis.png)
