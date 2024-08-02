# Introduction to Resourcer Pattern

The Resourcer design pattern exists to cleanly augment a set of data with methods to use it in various ways, relate deifferent resourced data lists together. It uses various caching techniques to optimize itself and automatically generates useful methods for data manipulation.

It makes use of two types of objects, `ListResourcer` and `ObjectResourcer`, and also adds a few methods to `ApplicationRecord`.

## ListResourcer

A `ListResourcer` is a core component of the Resourcer pattern. It is essentially a set of data that is augmented with methods for retrieving and managing related information about that data set. When a `ListResourcer` is created, it preloads related data and indexes it for efficient access. This helps in eliminating the N+1 query problem and makes data retrieval more performant and maintainable.

A `ListResourcer`:
- Pre-fetches and organizes related data upon initialization.
- Provides methods to access and manipulate this data.
- Uses lazy loading; it only loads data when/if it is actually needed.
- Uses caching techniques, ensuring efficient data retrieval.
- Is reusable across different parts of the application.

By using a `ListResourcer`, you can centralize the logic for data retrieval, making your codebase cleaner and more efficient.

## ObjectResourcer
 
An `ObjectResourcer` is created for each object within a `ListResourcer`. It allows access to the related data for a single object. The `ObjectResourcer` maintains a reference to its parent `ListResourcer`, which links it to other related `ListResourcers` and their `ObjectResourcers`.

An `ObjectResourcer`:
- Acts as a proxy for accessing related data.
- Extends the functionality of the base ActiveRecord object.
- Uses caching techniques, ensuring efficient data retrieval.
- Can delegate methods to the parent `ListResourcer` and to the ActiveRecord object it is attached to.

By using an `ObjectResourcer`, each object in your data set carries related data with it, making it easy to access and use, even when passed deeply into other nested methods.

## Changes to ApplicationRecord

The Resourcer pattern modifies the `ApplicationRecord` to add support for `ListResourcer` and `ObjectResourcer`. Every ActiveRecord object gets additional methods to interact with resourcers, ensuring a seamless integration.

### Added Methods:

- `resourcer`: Returns the specific resourcer assigned to the object or a default resourcer if none is assigned. This ensures that calls to methods like `object.resourcer.some_method` will not raise an error, provided that `some_method` is defined on the ActiveRecord object.
- `apply_resourcer`: Applies a `ListResourcer` to the object, creating an `ObjectResourcer` and assigning it to the object's `resourcer` property.
- `is_resourced?`: Checks if the object has a specific resourcer assigned. The default resourcer is not considered.
- `method_missing`: Delegates method calls to the resourcer if it responds to the method, allowing the resourcer to act as a proxy for methods defined on the resourcer.

These changes ensure that every ActiveRecord object can benefit from the Resourcer pattern, providing a robust and flexible way to manage and retrieve related data.

# Creating Resourcers

## Instantiating Resourcers

A Resourcer can be instantiated from an ActiveRecord relation, an array, or even a single ActiveRecord object

```ruby
# Instantiate with an array
company_list = Company.where(active: true).to_a
company_resourcer = CompanyResourcer.new(company_list)

# Instantiate with a relation
company_relation = Company.where(active: true)
company_resourcer = CompanyResourcer.new(company_relation)

# Instantiate with a single object
company = Company.find(1)
company_resourcer = CompanyResourcer.new(company)

# in all those cases, you can now do any of the following:
company_resourcer.list
company_resourcer.object_lookup
company_resourcer.id_list
```

You can also create an array of resourced objects from an ActiveRecord relation, an array, or a single ActiveRecord object using `.build`.

```ruby
# returns an array of resourced objects - NOT a resourcer
company_list = CompanyResourcer.build(Company.some_set_of_data)
company_list.first.resourcer # ObjectResourcer
company_list.first.resourcer.list_resourcer # ListResourcer
```

## Defining Resourcers

Resourcers should be defined inside the `app/resourcers` folder. The naming convention is to append `Resourcer` to the model name, ensuring consistency and clarity.

```ruby
# app/resourcers/company_resourcer.rb
class CompanyResourcer < Resourcer::ListResourcer
  relates_to :owner_account, :orders, :invoices
  index_by :creator_id
end
```

### Indexing Fields

The `index_by` method allows you to define fields to be indexed. This ensures that unique values and grouped objects can be accessed efficiently. See documentation on this method for more details on what methods this automatically generates.

```ruby
class CompanyResourcer < Resourcer::ListResourcer
  index_by :creator_id, :entity_type_id
end
```

### Relating to Other Resourcers

The `relates_to` method defines relationships to other resourcers. This method also implicitly calls `index_by` for the foreign key fields, thus creating all the methods that `index_by` creates.

```ruby
class CompanyResourcer < Resourcer::ListResourcer
  relates_to :owner_account, :orders
end
```

In this example, the `relates_to` method looks for associations named `owner_account` and `orders` on the `Company` model. It determines the class name of those models and looks for their resourcers (`AccountResourcer` and `OrderResourcer`), and sets up the necessary methods to access them.

It also automatically creates a way of accessing related objects through the resourcer:
```ruby
company = company_resourcer.first
company.resourcer.owner_account # automatically created as a wrapper...
company_resourcer.owner_account_resourcer.lookup(company.account_id) # ...to this
```

### Creating Custom Methods

Custom methods can be added to the `ObjectResourcerMethods` module within each `ListResourcer` subclass. These methods will be available on each individual object through its `resourcer` attribute.

```ruby
class CompanyResourcer < Resourcer::ListResourcer
  relates_to :owner_account, :orders
  delegate :order_items to: :orders_resourcer
  module ObjectResourcerMethods
    def total_order_item_value
      @total_order_item_value ||= order_items.sum(&:price)
    end
  end
end

company_list = Company.some_set_of_data
company_resourcer = CompanyResourcer.build(company_list)
company_resourcer.order_items # all order items for all companies

company = company_resourcer.list.first
company.resourcer.order_items # all order items for all order for this company
company.resourcer.total_order_item_value
```

This allows you to define custom behavior for each resourced object, enhancing the functionality and making data retrieval more intuitive.

This is the real powerhouse of the Resourcer pattern. Rather than adding a complex method directly to an ActiveRecord model that relies on a lot of related data, you can define it here to take advantage of all the related preloaded and indexed data. Such a method would only be usable on objects sourced from a set of data matching a query, but this is a common use case.

If that method were needed on a single, unresourced object, you could:
```ruby
CompanyResourcer.build(company).first.your_custom_method
```
Just a make a single object resourcer. NOTE: Future implementations of Resourcer might include a nicer way of doing this. Perhaps something like `company.single_resourcer.your_custom_method`

## Pass-through Behavior

The `.resourcer` attribute on an ActiveRecord responds to methods it inherits from ObjectResourcer, and also to custom methods you define in a ObjectResourcerMethods module. If you call a method on it which doesn't exist, however, it looks for that method in a couple other places: first its `ListResourcer`, and then the underlying ActiveRecord object it's attached to.
```ruby
class CompanyResourcer < Resourcer::ListResourcer
  def foo
      # ...
  end

  module ObjectResourcerMethods
    def bar
      # ...
    end
  end
end

class Company < ApplicationRecord
  def baz
  # ...
  end
end

# All of these work
company.resourcer.foo
company.resourcer.bar
company.resourcer.baz
```
If the method called in this way doesn't exist on either `.resourcer`, or the `ListResourcer` it came from, or `company`, an error is raised.

This also means you can access related resourcers like so:
```ruby
company.resourcer.owner_account.resourcer.website
company.resourcer.owner_account_resourcer.lookup(account_id)
```

# Changes to ApplicationRecord

To support the Resourcer pattern, several methods are added to all `ActiveRecord` objects. These methods enable seamless integration of resourcers, allowing objects to access their related data efficiently and intuitively.

## Added Instance Methods

### `resourcer`

The `resourcer` method provides access to an `ObjectResourcer` for the given object. If a specific resourcer is assigned to the object, it returns that resourcer; otherwise, it returns a default resourcer.

```ruby
company_list = CompanyResourcer.build(Company.some_list)
company = company_list.first
company.resourcer # => ObjectResourcer for the company object
other_company = Company.find(1)
other_company.resourcer # a blank resourcer, but not useful for much
```

**Why do we have a default resourcer?** The default resourer on objects is simply a passthrough. If you call a method on it, it just delegates that method to the ActiveRecord object it's attached to. This is primarily to allow for cleaner code. For example, both of these lines evaluate the same way:
```ruby
company.is_resourced? ? company.resourcer.owner_account : company.owner_account
company.resourcer.owner_account
```
In the second line, it'll use the resourcer to more efficiently get the account if it can, otherwise fall back to `company.account`

### `auto_resourcer`

`.auto_resourcer` is going to be the same as `.resourcer` if `.is_resourced?` is true. If not, it instantiates a brand new `ObjectResourcer` for our company (it's memoized, so this only happens once for the object) and returns it for use. It's the same as running `resourcer_klass.build(self).first.resourcer`. This provides a mechanism to work with our company as a resourced object. It's either resourced as part of a larger set of objects, or a smaller set containing only this object.

```ruby
company = Company.first # an un-resourced object
company.auto_resourcer.order_id_list # we may still interact with it as a resourced object
company.is_resourced? # still false
```

### `apply_resourcer`

The `apply_resourcer` method applies a `ListResourcer` to the object, creating an `ObjectResourcer` and assigning it to the object's `resourcer` property. This method returns the object itself to allow for method chaining. it's the inverse of `list_resourcer.apply_to(object)`.

```ruby
account = Account.first
company.is_resourced? # false
account.apply_resourcer(account_list_resourcer) # => sets .resourcer attribute
company.is_resourced? # true
```

### `is_resourced?`

The `is_resourced?` method checks if the object has a specific resourcer assigned. Even though all models will respond to `.resourcer`, only objects coming from a resourced data set will return `true` to this method.

## Added ApplicationRecord Class Methods

### `resourcer_class_name`

The `resourcer_class_name` method returns the class name of the resourcer for the model.

```ruby
Account.resourcer_class_name # => "AccountResourcer"
```

### `resourcer_klass`

The `resourcer_klass` method returns the constantized class of the resourcer for the model.

```ruby
Account.resourcer_klass # => AccountResourcer
```

By adding these methods to `ApplicationRecord`, the Resourcer pattern integrates seamlessly with ActiveRecord models, providing a powerful and flexible way to manage and access related data.

# ListResourcer

The `ListResourcer` class is a foundational component of the Resourcer pattern. It enhances data retrieval and management by pre-fetching and indexing necessary data, thereby enabling efficient access to related data without additional database queries.

## Instance Methods

### `assimilate(list)`

The `assimilate` method processes a given list of objects, referencing the `index_by` and `relates_to` rules defined on the the specific ListResourcer subclass to a build indexess and groups. It assigns itself to the `.resourcer` attribute of each object in the list.

```ruby
company_list_resourcer.assimilate(Company.a_bunch_of_companies)
```

### `id_list`

The `id_list` method returns an array of all IDs (primary key values) of the objects managed by the resourcer. This is an alias to `object_id_list`. This won't work for classes that don't have primary keys.

```ruby
company_list_resourcer.id_list
```

### `object_lookup`

The `object_lookup` method returns a hash of all objects managed by the resourcer, indexed by their primary key. This won't work for classes that don't have primary keys.

```ruby
company_list_resourcer.object_lookup
```

### `lookup(key)`

The `lookup` method retrieves the object with the given primary key. If the key is an array, it returns an array of matching objects. These are objects stored in the `object_lookup` hash. This won't work for classes that don't have primary keys.

```ruby
company = company_list_resourcer.lookup(company_id)
companies = company_list_resourcer.lookup([company_id1, company_id2])
```

### `list`

The `list` method returns an array of all objects managed by the resourcer. This is an alias to `object_list`. This method will work whether a class does or doesn't have a primary key.

```ruby
company_list = company_list_resourcer.list
```

### `unique_values`

The `unique_values` method returns a hash of all unique values for fields configured to be index by use of `index_by` (or implicitly via `relates_to`).

```ruby
unique_values = company_list_resourcer.unique_values
unique_values = company_list_resourcer.unique_values[:creator_id]
```

### `unique_values_for(fieldname)`

Wrapper method for accessing `unique_values`.

```ruby
unique_creator_ids = company_list_resourcer.unique_values_for(:creator_id)
```

### `grouped_object_lookup`

The `grouped_object_lookup` method returns a hash of grouping information all indexed values.

```ruby
# returns a hash that is keyed by fieldname, then by a specific field value,
# which evaluates to an array of objects with that value for that field
grouped_objects = company_list_resourcer.grouped_object_lookup
```

### `grouped_object_lookup_for(fieldname)`

The `grouped_object_lookup_for` method returns a hash of all objects managed by the resourcer, grouped by the given field. A wrapper method for `grouped_object_lookup`.

```ruby
# `grouped_object_lookup_for` returns something like:
# { 5234 => { # account id
#     876449 => { ... } # resourced company, indexed by company id
#     856430 => { ... } # another resourced company
#   },
#  ...
# }
companies_by_creator_id = company_list_resourcer.grouped_object_lookup_for(:creator_id)
companies_by_creator_id[creator_id] # hash of all companies with this creator_id value
companies_by_creator_id[creator_id][company_id] # specific company (if it has that creator_id)
```

### `list_for(fieldname, key)`

The `list_for` method retrieves the list of objects with the given value for the specified field. Uses `grouped_object_lookup_for`, but cleaner to work with.

```ruby
companies_for_creator = company_list_resourcer.list_for(:creator_id, creator_id)
```

### `apply_to(obj)`

The `apply_to` method sets the `.resourcer` attribute of the provided object. It's the inverse of `object.apply_resourcer(list_resourcer)`.

```ruby
company_list_resourcer.apply_to(company)
```

### `build_object_resourcer(obj)`

The `build_object_resourcer` method creates an `ObjectResourcer` for the given object, extending it with the `ObjectResourcerMethods` module defined in the appropriate subclass of `ListResourcer`.

```ruby
object_resourcer = company_list_resourcer.build_object_resourcer(company)
```

### Alias Methods

For convenience, many alias methods are available to reference certain information using the name of the class being managed by a resourcer. So, for CompanyResourcer, the following are available:

```ruby
company_list = Company.some_set_of_data
company_resourcer = CompanyResourcer.build(company_list)

company_resourcer.company_list # alias to company_resourcer.list
company_resourcer.company_id_list # alias to company_resourcer.id_list
company = company_resourcer.company_lookup(company_id) # alias to company_resourcer.lookup

company.resourcer.company # alias to company.resourcer.object (which is the company)
```

## ListResourcer Class Methods

### `build(object_list)`

The `build` method creates a new `ListResourcer` object of the appropriate subclass, assimilating the given list of objects. Accepts a relation, array, or ActiveRecord object as input. Returns an array of resourced ActiveRecord objects by calling `.list` on the newly created `ListResourcer`

```ruby
company_list_resourcer = CompanyResourcer.build(Company.my_favorite_companies)
```

### `index_by(*fieldnames)`

The `index_by` method defines fields to be indexed, allowing retrieval of unique values and grouped objects by these fields. It adds dynamic methods for accessing these values.

```ruby
class CompanyResourcer < Resourcer::ListResourcer
  index_by :creator_id, :entity_type_id
end

company_resourcer = CompanyResourcer.new(Company.some_query)
company_resourcer.unique_entity_type_id_list # array of all unique entity_type_id values
company_resourcer.grouped_by_creator_id # hash of resourced companies keyed by :creator_id values
company_resourcer.list_for_creator_id(creator_id) # all companies with that creator_id
```

### `relates_to(*associations)`

The `relates_to` method defines relationships to other models, generating methods for `belongs_to` and `has_many` associations. Note that this automatically invokes `index_by` on the foreign key fields used in these relationships.

```ruby
class CompanyResourcer < Resourcer::ListResourcer
  relates_to :owner_account, :orders
end
```

### `managed_klass`

The `managed_klass` method returns the class that is being managed by the resourcer class.

```ruby
CompanyResourcer.managed_klass # => Company
```

## Dynamically Generated Methods

Using `index_by` dynamically generates methods for working with relational data. `relates_to` automatically calls `index_by` on foreign key fields used in relating models. The following would dynamically create several such methods:

```ruby
class CompanyResourcer < Resourcer::ListResourcer
  relates_to :owner_account, :orders
  index_by :entity_type_id
  delegate :order_item_resourcer, to: :order_resourcer

  delegate :order_item_list, to: :order_item_resourcer
end
```

### Methods Generated by `index_by`

The `index_by` method generates the following methods for each field it indexes:

- `unique_<fieldname>_list`: Returns an array of unique values for the specified field.
- `grouped_by_<fieldname>`: Returns a hash where the keys are the unique values of the specified field, and the values are arrays of objects that have that field value.
- `list_for_<fieldname>(key)`: Returns an array of objects that have the specified field value.

```ruby
class CompanyResourcer < Resourcer::ListResourcer
  index_by :creator_id, :entity_type_id
end

company_resourcer = CompanyResourcer.build(Company.all)
unique_creator_ids = company_resourcer.unique_creator_id_list
grouped_by_creator_id = company_resourcer.grouped_by_creator_id
companies_for_creator = company_resourcer.list_for_creator_id(creator_id)
```

### Methods Generated by `relates_to`

The `relates_to` method generates methods to access related resourcers and the objects they manage. For each association, it creates:

- `<association>_resourcer`: Returns the resourcer for the associated model.
- `<association>_id_list`: Returns an array of IDs for the associated objects.
- `<association>_list`: Returns an array of the associated objects.
- `<association>_lookup`: Returns a hash of associated objects indexed by their primary key.

```ruby
class CompanyResourcer < Resourcer::ListResourcer
  relates_to :owner_account, :orders
end

company_resourcer = CompanyResourcer.build(Company.all)
owner_account_resourcer = company_resourcer.owner_account_resourcer
owner_account_ids = company_resourcer.owner_account_id_list
owner_accounts = company_resourcer.owner_account_list
owner_account_lookup = company_resourcer.owner_account_lookup
```

It also adds an easy way of getting related objects through a resourced object by generating a method named after each parameter to `relates_to`

```ruby
company = company_resourcer.list.first
owner_account = company.resourcer.owner_account
orders = company.resourcer.orders
```

## Working With Associations

```ruby
company_resourcer = CompanyResourcer.new(Company.within_state('WA'))
# all accounts relating to any companies from the original list
owner_accounts = company_resourcer.owner_account_list
# all orders relating to any companies from the original list
orders = company_resourcer.order_list
# all order items relating to any orders for any companies from the original list
order_items = company_resourcer.order_item_list

# objects returned by a Resourcer are always already resourced...
order_items.each do |order_item|
  order_item.account # assuming OrderItemResourcer specifies how to get .account
end
```