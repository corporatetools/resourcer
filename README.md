# Resourcer Pattern

The Resourcer Pattern is a design pattern that augments ActiveRecord objects with additional information, preloading related data efficiently and providing easy access to it. This pattern aims to eliminate N+1 query problems and centralize the complexities of loading related data, retrofitting it onto any queried data set. The core idea is to “pack” the big picture into each object, ensuring it carries related data with it, usable even when passed deeply into other nested methods.

- For more about why this exists: [Purpose of Resourcer Pattern](lib/resourcer/documentation/purpose.md)
- For full documentation: [Documentation](lib/resourcer/documentation/documentation.md)

## Key Components

### Resourcer::ListResourcer

The ListResourcer class is the base class for creating resourcers for each model. It handles a relation or array of ActiveRecord objects, preloading related data and augmenting the data with additional information. Methods can be customized for referencing specific sets of data.

### Resourcer::ObjectResourcer

Each object in a ListResourcer gets its ObjectResourcer, which allows access to the related data for a single object. The ObjectResourcer maintains a reference to the ListResourcer that spawned it, linking it to related ListResourcers and their ObjectResourcers.

### Resourcer::ListResourcer::ObjectResourcerMethods

This module contains methods mixed into each ObjectResourcer. Each ListResourcer subclass can customize its own ObjectResourcerMethods module to define custom methods for the object resourcers of that class.

## Key Benefits

- **Eliminates N+1 Queries:** By preloading related data, the pattern avoids repeated database hits.
- **Centralized Complexity:** Defines the complexities of loading related data in a single place, making it easy to retrofit onto any queried data set.
- **Lazy Loading:** Only loads associations when needed, optimizing performance.
- **Pre-existing Model Reflections:** Uses model reflections to determine associations, reducing relational information replication.
- **Reduced Coupling:** When used with delegators, it reduces model coupling.
- **No SQL Joins:** Uses preloaded ID lists instead of SQL joins, speeding up queries.
- **Universal Application:** Can be used on any ActiveRecord object, providing a safe way to reference associations through the resourcer.

> **Note:** There is a tradeoff between memory and speed. More data is loaded into memory, but database load is greatly reduced. This is ideal for pages that deal with displaying lists of data.

## Example Usage

### Basic Usage

```ruby
# Basic usage example

account_id_list = ['eeba3947-b1a8-4485-992b-2f245a317f46', '2e6ef539-bcd3-47c2-8316-ce8ecbe2defc']
company_relation = Company.by_owner_account(account_id_list)

company_list_resourcer = CompanyResourcer.new(company_relation)
company_list_resourcer.owner_account_list.size # Queries accounts table and resources all objects
company_list_resourcer.order_list.size # Loads all orders related to all companies

Account.fetchable(account_id_list.first) # No query needed

company = company_list_resourcer.list.first
account = company.resourcer.owner_account # No query - already queried for owner_account_list.size
website = account.resourcer.website # First website query - loads all websites related to all companies
```

### Handling Associations

```ruby
# Accessing related ListResourcer objects

company.resourcer.website_resourcer # ListResourcer for all websites related to all companies
company.resourcer.website_resourcer.id_list

company_2 = company_list_resourcer.list[1]
company_2.resourcer.website # No query
```

### Passthrough and Deferred Loading

```ruby
# Passthrough example

company.resourcer.subscriptions.to_sql # Resourcer currently has no knowledge of subscriptions, so it passes through
company.resourcer.order_items.count # Gets order items for ALL companies and retrieves result
company_2.resourcer.order_items.count # No query, even though it's a different company
```

### Applying Resourcers

```ruby
# Using resourcer on objects, even if they are not initially resourced

company_3 = company_relation.first
company_3.is_resourced?             # False
company_3.resourcer.owner_account   # This works, just not with benefits of a resourcer. Just a passthrough
company_3.apply_resourcer(company_list_resourcer) # Now it's resourced
company_3.is_resourced?             # True
company_3.resourcer.owner_account   # No query - now it's resourced

voucher = Voucher.first   # VoucherResourcer doesn't even exist
voucher.is_resourced?     # False
voucher.resourcer.company # But this still works, because all ActiveRecord objects are given a default passthrough resourcer
```

### Nested Relationships
```ruby
# CompanyResourcer doesn't have anything built in for account owners, or their contact info, but...

company.resourcer.owner_account.resourcer.owner.resourcer.person_addresses.first # Loads everything once
company_2.resourcer.owner_account.resourcer.owner.resourcer.person_addresses.first # No query!

# Access related ListResourcer objects, even if they are multiple levels away
company.resourcer.website_resourcer     # list_resourcer for all websites related to all companies
company.resourcer.owner_account.resourcer.owner.resourcer.list_resourcer.id_list
```

### Other Methods
```ruby
# Accessing additional methods and lookups

company_list_resourcer.list             # Array of pre-resourced companies
company_list_resourcer.id_list          # Array of company ids
company_list_resourcer.object_lookup    # Hash of pre-resourced companies, indexed by their primary key
company_list_resourcer.lookup(id)       # Look up a company by id
company_list_resourcer.lookup([id, id]) # Look up multiple companies by id

# Since CompanyResourcer `relates_to :orders` :
company_list_resourcer.order_id_list    # array of ids
company_list_resourcer.order_list       # array of pre-resourced orders
company_list_resourcer.order_lookup     # hash of pre-resourced orders, indexed by their primary key
company_list_resourcer.order_resourcer  # OrderResourcer loaded with all orders related to the set of companies
company_list_resourcer.order_resourcer.list_for_company_id(id) # custom method defined on OrderResourcer
```

### Indexing Fields
```ruby
# Indexing fields and accessing related ListResourcer objects
company_list_resourcer.unique_values_for(:creator_id)
company_list_resourcer.unique_creator_id_list                                   # same as above
company_list_resourcer.unique_entity_type_id_list                               # FAILS - entity_type_id is not pre indexed via `indexed_by` or `relates_to` in CompanyResourcer
company_list_resourcer.unique_values_for(:entity_type_id)                       # this still works - index is built on the fly
company_list_resourcer.grouped_object_lookup                                    # hash of all companies, grouped by indexed_fields
company_list_resourcer.grouped_object_lookup_for(:entity_type_id)[entity_type]  # all companies matching entity_type
company_list_resourcer.list_for_domestic_registration_id(id)
company_list_resourcer.service_resourcer.list_for_company_id(id)
```
