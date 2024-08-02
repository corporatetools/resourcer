 # Purpose of Resourcer Pattern

## 00. Understanding N+1

Let's imagine the following simple models from our application:

```ruby
# models/account.rb
class Account < ApplicationRecord
  has_many :companies
end

# models/company.rb
class Company < ApplicationRecord
  belongs_to :owner_account, foreign_key: :creator_id, class_name: "Account"
  has_many :orders
end

# models/order.rb
class Order < ApplicationRecord
  belongs_to :company
  has_many :order_items
end

# models/order_item.rb
class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :filing
end

# models/filing.rb
class Filing < ApplicationRecord
  has_many :order_items
end
```

### Example 1

Let's imagine we were to iterate through that whole stack like so:

```ruby
class ReportsController < ApplicationController
  def index
    accounts = Account.some_searched_data
    accounts.each do |account|
      puts "Account: #{account.id}"
      account.companies.each do |company|
        puts "  Company: #{company.id}"
        company.orders.each do |order|
          puts "    Order: #{order.id}"
          order.order_items.each do |order_item|
            puts "      OrderItem: #{order_item.id}"
          end
        end
      end
    end
  end
end
```

If we have 10 accounts, each with 5 companies, and each company with 10 orders, and each order with 5 order items, this approach would result in:

- 1 query for accounts
- 10 queries for companies
- 50 queries for orders
- 500 queries for order items

That’s a total of 561 queries! This illustrates the N+1 query problem, where the number of queries grows exponentially with the number of records. If we additionally wanted to show information about the filing for each order item, it would add an additional 500 queries!

### Example 2

If we were to approach that stack backwards, starting with a set of order items matching a query across many different accounts, it would look like this:

```ruby
class ReportsController < ApplicationController
  def index
    order_items = OrderItem.some_searched_data
    order_items.each do |order_item|
      order = order_item.order
      company = order.company
      account = company.owner_account
      puts "OrderItem ID: #{order_item.id}, Order Number: #{order.id}, " + 
        "Company Name: #{company.name}, Account Name: #{account.name}"
    end
  end
end
```

If we have 100 order items, each belonging to different orders, companies, and accounts, this approach would result in:

- 1 query for order items
- 100 queries for orders
- 100 queries for companies
- 100 queries for accounts

That’s a total of 301 queries, even if all 100 order items were on a single order for a single account/company. Again, including information from filings requires an additional query for every order item.

## 01. Solving N+1 with includes

Rails provides some fantastic ways to preemptively load data across all the tables in use to avoid this problem in many scenarios. Consider the following simple example:

```ruby
class Company < ApplicationRecord
  def most_recent_filing
    OrderItem.where(order: orders).joins(:filing).order('filings.created_at DESC').first&.filing
  end
end

class ReportsController < ApplicationController
  def index
    companies = Company.includes(:owner_account, :orders).some_searched_data

    companies.each do |company|
      owner_account = company.owner_account
      most_recent_filing = company.most_recent_filing

      puts "#{company.name} (Account ##{owner_account&.id}) " + 
        "- Most Recent Filing: #{most_recent_filing&.name}"
    end
  end
end
```

This starts to get to the real issue. A simple method added to Company to get its most recent filing. Once this is buried in a loop, the extra query will be invoked on each iteration. The addition of `.includes` does help some, but won't help with the queries against `order_items` or `filings`.

Also, using `.includes` requires knowledge of what's happening inside that method. Imagine the method makes use of other models/methods in a whole chain. There's no practical way of knowing from the outset what should be included in order to optimize. The bigger issue however is that using `.includes` here violates basic decoupling principles of programming; the `index` method SHOULD NOT know or care what's going on inside that method.

If we're looping through a lot of records, this seemingly simple code is going to be very inefficient due to the number of queries it generates, and will not scale well.

Summarizing, here are a few key drawbacks of `.includes`:

- **Efficiency**: This is fine for smaller data sets, but the query joins that result from many large tables can be very slow and memory-intensive. With large datasets, it's often more efficient to query records from each table separately rather than using joins.
- **Duplicates knowledge of join conditions**: Every place throughout the code that tries to iterate over the data using the `.includes` approach duplicates the knowledge of how those tables are joined. When there are many `.includes` statements throughout the code that all repeat the same associations, this violates basic DRY coding principles. In fact, it's often difficult to use `.includes` without repeating yourself; it's usually impractical to make reusable.
- **Increased Coupling**: Preemptively using `.includes` on a query because you know that a method acting on that query uses the included data couples the method to the caller to closely. The caller shouldn't have knowledge or expectation of how the method works.
- **Limited Flexibility**: While `.includes` works well for straightforward associations, it may not provide the flexibility needed for more complex data loading scenarios. Custom logic and optimizations are harder to implement using `.includes`.

## 02. An Alternative Solution

Rather than leaning on includes, an alternative approach is to essentially manually do what `.includes` tries to do for us: build hashes as lookups from which we can get all our data. We query the needed tables up front, once for each table, and go from there:

```ruby
class ReportsController < ApplicationController
  def index
    companies = Company.some_searched_data
    
    accounts = Account.where(id: companies.map(&:creator_id)).index_by(&:id)
    orders = Order.where(company: companies).index_by(&:id)
    order_items = OrderItem.where(order: orders.values).joins(:filing).index_by(&:id)
    
    most_recent_filing_by_company_id = {}
    order_items.each do |order_item_id, order_item|
      company_id = orders[order_item.order_id].company_id
      if !most_recent_filing_by_company_id[company_id]
        most_recent_filing_by_company_id[company_id] = order_item.filing
      elsif order_item.filing.created_at > most_recent_filing_by_company_id[company_id].created_at
        most_recent_filing_by_company_id[company_id] = order_item.filing
      end
    end
  
    companies.each do |company|
      owner_account = accounts[company.creator_id]
      most_recent_filing = most_recent_filing_by_company_id[company.id]
    
      puts "#{company.name} (Account ##{owner_account&.id}) " + 
        "- Most Recent Filing: #{most_recent_filing&.name}"
    end
  end
end
```
  
Upside: This puts us in complete control of what data is loaded and how it's processed, eliminating all unnecessary queries. This is going to scale really well, and we'll only use four queries no matter how large our data set.
  
There are some downsides, though.

- It's a lot uglier to read
- It's still way too intimately coupled to the structure of tables and their foreign keys
- It's not very reusable, and we don't want to have to keep rebuilding this kind of thing every time we want to loop through data.
- None of the optimization is applied to the company object directly. `.includes` enhances the objects within a data set so that the related (included) models can be accessed directly on the object (ie `company.owner_account`)

Basically, it comes with all the same problems as using `.includes`, and does it in a much harder to read way... but at least it's faster?!?

What we need is a way to get the benefits of this approach, while fixing the drawbacks (or at least not making them worse).
  
### Resourcer Pattern
  
The Resourcer pattern exists to abstract a lot of that complexity away, make it reusable, and leave you with code like this:
  
```ruby
class ReportsController < ApplicationController
  def index
    company_list = Company.some_searched_data
    CompanyResourcer.build(company_list).each do |company|
      puts "#{company.name} (Account ##{company.resourcer.owner_account&.id}) " + 
        "- Most Recent Filing: #{company.resourcer.most_recent_filing&.name}"
    end
  end
end
```
  
All of the benefits of our alternative solution, but with none of the downsides!

At a high level, here's how it works:

- It's automatically creating a series of index hashes like our ugly solution
- It's managing all those indexes inside an object which is attached to each object in the set we're iterating over
- Those indexes (called a resourcers) are defined in a way that is reusable everywhere
- Each of those resourcers are lazy loaded, so they are only loaded once they are needed, and aren't loaded if they're not needed.

## 03. Resourcer Basics

To start with resourcers, we define them inside the `app/resourcers` folder:

```ruby
# lib/resourcer/account_resourcer.rb
class AccountResourcer < Resourcer::ListResourcer
  relates_to :companies
end

# lib/resourcer/company_resourcer.rb
class CompanyResourcer < Resourcer::ListResourcer
  relates_to :account, :orders
end

# lib/resourcer/order_resourcer.rb
class OrderResourcer < Resourcer::ListResourcer
  relates_to :company, :order_items
end

# lib/resourcer/order_item_resourcer.rb
class OrderItemResourcer < Resourcer::ListResourcer
  relates_to :order, :filing
end

# lib/resourcer/filing_resourcer.rb
class FilingResourcer < Resourcer::ListResourcer
  relates_to :order_items
end
```

These are some fairly simple resourcers. You'll note that they are configured to relate to one another, without explicitly stating how. This is because they automatically look at the names passed to `relates_to` and look for relations on the ActiveRecord models with the same names to extract relationship information automagically.

***NOTE:** In the future, resourcers could be improved to automatically read through and replicate associations between models instead of having to define them like this.*

Now let's look at a more complicated Resourcer:

```ruby
# lib/resourcer/company_resourcer.rb
class CompanyResourcer < Resourcer::ListResourcer
  relates_to :account, :orders
  delegate :order_item_resourcer, to: :orders_resourcer
  delegate :filing_resourcer, to: :order_item_resourcer

  delegate :order_item_list, to: :order_item_resourcer

  def order_items_by_company_id
    @order_items_by_company_id ||= begin
      result = Hash.new { |hash, key| hash[key] = [] }
      order_item_resourcer.list.each do |order_item|
        order = order_resourcer.lookup(order_item.order_id)
        result[order.company_id] << order_item
      end
      result
    end
  end

  module ObjectResourcerMethods
    def order_items
      @order_items ||= list_resourcer.order_items_by_company_id[company.id] || []
    end

    def filings
      @filings ||= order_items.map{ |oi| filing_resourcer.lookup(oi.filing_id) }
    end

    def most_recent_filing
      @most_recent_filing ||= filings.max_by(&:created_at)
    end
  end
end
```

Let's walk through this:

- **relates_to :account, :orders**: This indicates that `CompanyResourcer` relates to `account` and `orders`. It will automatically set up the relationships based on ActiveRecord relationships and only lazy load the additional resourcers when/if needed.
- **delegate :order_item_resourcer, to: :orders_resourcer**: This delegates the `order_item_resourcer` method to the `orders_resourcer`, allowing us to preload and access all the order items related to all orders for any company in this Resourcer.
- **order_items_by_company_id**: This demonstrates how to augment our data set with a method. It creates a hash where the keys are company IDs and the values are arrays of order items related to each company.
- **ObjectResourcerMethods**: This module contains methods that will be available on each individual company object through its resourcer. When looping through companies, each company will have a `.resourcer` attribute, which will respond to any methods available on the `ListResourcer` (such as `order_items_by_company_id` and a bunch of automatically generated methods), as well as the object specific methods defined in `ObjectResourcerMethods`, such as `.filings`
- **Memoization**: All methods are memoized, because this pattern is intended as an optimized way of reading data from a query result set. New resourcers should be created for up-to-date data if objects are updated.

### Example Usage

With the above resourcer definitions, our controller code becomes much cleaner and more efficient:

```ruby
class ReportsController < ApplicationController
  def index
    company_list = Company.some_searched_data
    CompanyResourcer.build(company_list).each do |company|
      puts "#{company.name} (Account ##{company.resourcer.owner_account&.id}) " + 
        "- Most Recent Filing: #{company.resourcer.most_recent_filing&.name}"
    end
  end
end
```

This approach leverages the CompanyResourcer to efficiently preload and manage related data, avoiding the N+1 query problem and keeping the code clean and maintainable.

By using the Resourcer pattern, we achieve solve N+1 without all the downsides of the previous approaches, and end up with some very clean and maintainable code!

### A Better Example

Consider this method on the `Company` model:
```ruby
  def has_not_registered?
    order_ids = Order.where(company_id: id).pluck(:id)

    OrderItem
      .where(order_id: order_ids)
      .where(
        product_categorization_id: ProductCategorization.register_a_company_categorization.id
      )
      .where.not(
        status: NOT_FORMED_STATUSES
      )
      .none?
  end
```
We have a lot of methods like this. Any code that calls this method cannot optimize it by utilizing `.includes`, and again that would violate decoupling principles anyway. Calling this method on a single `Company` object is not a big deal, but calling this inside a loop that iterates through a lot of companies is bad news. Every iteration will invoke three additional queries for `Order`, `OrderItem`, and `ProductCategorization`. What's really bad is when methods like this call other methods like this, and our inefficiencies get exponentially worse!

While there are a lot of other ways to approach this problem, most of them are more difficult than might be practical to try. If a quick win is needed, the `CompanyResourcer` we just created is a solid option.

We can change it like so:
```ruby
  def has_not_registered?
    category_id = ProductCategorization.register_a_company_categorization.id

    if is_resourced?
      resourcer.order_items.select { |order_item|
        order_item[:product_categorization_id] == category_id &&
        ! NOT_FORMED_STATUSES.include?(order_item[:status])
      }.none?
    else
      order_ids = Order.where(company_id: id).pluck(:id)

      OrderItem
        .where(order_id: order_ids)
        .where(product_categorization_id: category_id)
        .where.not(status: NOT_FORMED_STATUSES)
        .none?
    end
  end
```
If this company is resourced, we already have efficient access to all the order items as an array that we can manipulate without invoking the database. Otherwise, we're continuing with the original logic. There are a lot of other optimizations and cleanup that can/should be done here, but are outside the present scope of discussion. We're leaving any optimizations to `ProductCategorization` out of our refactor, for example.

The biggest drawback to our approach is the duplicated logic between the if and else. There are several solutions to this. One possibility provided by `Resourcer` is `auto_resourcer`:
```ruby
  def has_not_registered?
    category_id = ProductCategorization.register_a_company_categorization.id
    auto_resourcer.order_items.select { |order_item|
      order_item[:product_categorization_id] == category_id &&
      ! NOT_FORMED_STATUSES.include?(order_item[:status])
    }.none?
  end
```
`.auto_resourcer` is going to be the same as `.resourcer` if `.is_resourced?` is true. If not, it instantiates a brand new `ObjectResourcer` for our company (it's memoized, so this only happens once for the object) and returns it for use. It's the same as running `resourcer_klass.build(self).first.resourcer`. Remember `ObjectResourcer` instances are always part of a set of data, built into a `ListResource`. In this case, the "set" of data is this one, single object.

Either way, this provides a mechanism to work with our company as a resourced object. It's either resourced as part of a larger set of companies, or a smaller containing only this company. At best, we get huge efficiency savings if it's part of a larger set, and at worse we at least get a small boost and access to custom methods created on `CompanyResourcer`. For example, we can access `order_items` directly, which is not built into `Company`.

One thing of note here: the original version of the method did only query for `OrderItem` results matching certain criteria, whereas our current solution is grabbing all order items for all orders. This is potentially less efficient in some cases. There are solutions to this, although in many case such solutions aren't needed and we're ignoring that for the sake of brevity in our example.

## 04. More Details

When iterating through a set of data that has been augmented with `ListResourcer`, each object will respond `true` to its `.is_resourced?` method. It should be noted that all ActiveRecord models will have a `.resourced` attribute, which just acts as a pass through proxy if the object isn't resourced. This means that we can call `child_object.resourcer.parent_object` even if `child_object` isn't resourced; it'll just pass through to `child_object.parent_object`. If it si resourced, then it'll utilize the benefits of the resourcer. This just helps code look cleaner in many cases by reducing how often we need to check `.is_resourced?`.

The `.resourcer` on an AR object is an `ObjectResourcer`, created as part of a `ListResourcer`, and it knows that it's part of a larger context. That's how it provides its benefits. Because all this context is attached directly to the object, this context is still accessible even when the object is passed and re-passed through a chain of methods. This is great when the object is being passed through a presenter, or a helper, or a series of methods intended to help with the display of the object.

It's important to understand, however, that Resourcer makes use of caching techniques like RequestStore and memoization to keep things running smoothly. RequestStore never persists beyond the life cycle of a single request, so we don't have to worry about invalidating cache between requests. A Resourcer should not be used for code that makes alterations on data and be expected to update! If you want the latest data after making updates to data, you must build a new Resourcer.

This means it shouldn't be used inside of methods that are expected to always run queries for the latest data. For an existing large application with a lot of very slow methods that work by actively querying for a lot of data to get a result, using Resourcer inside of complex model methods can bring huge speed gains, but you should be certain that those methods are not expected to provide fresh results every time they're called, or Resourcer is not the tool for the job.