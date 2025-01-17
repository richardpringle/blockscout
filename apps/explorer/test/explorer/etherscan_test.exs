defmodule Explorer.EtherscanTest do
  use Explorer.DataCase

  import Explorer.Factory

  alias Explorer.{Etherscan, Chain}
  alias Explorer.Chain.{Transaction, Wei}

  describe "list_transactions/2" do
    test "with empty db" do
      address = build(:address)

      assert Etherscan.list_transactions(address.hash) == []
    end

    test "with from address" do
      address = insert(:address)

      transaction =
        :transaction
        |> insert(from_address: address)
        |> with_block()

      [found_transaction] = Etherscan.list_transactions(address.hash)

      assert transaction.hash == found_transaction.hash
    end

    test "with to address" do
      address = insert(:address)

      transaction =
        :transaction
        |> insert(to_address: address)
        |> with_block()

      [found_transaction] = Etherscan.list_transactions(address.hash)

      assert transaction.hash == found_transaction.hash
    end

    test "with same to and from address" do
      address = insert(:address)

      _transaction =
        :transaction
        |> insert(from_address: address, to_address: address)
        |> with_block()

      found_transactions = Etherscan.list_transactions(address.hash)

      assert length(found_transactions) == 1
    end

    test "with created contract address" do
      address = insert(:address)
      contract_address = insert(:contract_address)

      transaction =
        :transaction
        |> insert(from_address: address, to_address: nil)
        |> with_contract_creation(contract_address)
        |> with_block()

      %{created_contract_address_hash: contract_address_hash} =
        :internal_transaction_create
        |> insert(transaction: transaction, index: 0)
        |> with_contract_creation(contract_address)

      [found_transaction] = Etherscan.list_transactions(contract_address_hash)

      assert found_transaction.hash == transaction.hash
    end

    test "with address with 0 transactions" do
      address1 = insert(:address)
      address2 = insert(:address)

      :transaction
      |> insert(from_address: address2)
      |> with_block()

      assert Etherscan.list_transactions(address1.hash) == []
    end

    test "with address with multiple transactions" do
      address1 = insert(:address)
      address2 = insert(:address)

      3
      |> insert_list(:transaction, from_address: address1)
      |> with_block()

      :transaction
      |> insert(from_address: address2)
      |> with_block()

      found_transactions = Etherscan.list_transactions(address1.hash)

      assert length(found_transactions) == 3

      for found_transaction <- found_transactions do
        assert found_transaction.from_address_hash == address1.hash
      end
    end

    test "includes confirmations value" do
      insert(:block)
      address = insert(:address)

      transaction =
        :transaction
        |> insert(from_address: address)
        |> with_block()

      insert(:block)

      [found_transaction] = Etherscan.list_transactions(address.hash)

      {:ok, max_block_number} = Chain.max_block_number()
      expected_confirmations = max_block_number - transaction.block_number

      assert found_transaction.confirmations == expected_confirmations
    end

    test "loads created_contract_address_hash if available" do
      address = insert(:address)
      contract_address = insert(:contract_address)

      transaction =
        :transaction
        |> insert(from_address: address, to_address: nil)
        |> with_contract_creation(contract_address)
        |> with_block()

      %{created_contract_address_hash: contract_hash} =
        :internal_transaction_create
        |> insert(transaction: transaction, index: 0)
        |> with_contract_creation(contract_address)

      [found_transaction] = Etherscan.list_transactions(address.hash)

      assert found_transaction.created_contract_address_hash == contract_hash
    end

    test "loads block_timestamp" do
      address = insert(:address)

      %Transaction{block: block} =
        :transaction
        |> insert(from_address: address)
        |> with_block()

      [found_transaction] = Etherscan.list_transactions(address.hash)

      assert found_transaction.block_timestamp == block.timestamp
    end

    test "orders transactions by block, in ascending order (default)" do
      first_block = insert(:block)
      second_block = insert(:block)
      address = insert(:address)

      2
      |> insert_list(:transaction, from_address: address)
      |> with_block(second_block)

      2
      |> insert_list(:transaction, from_address: address)
      |> with_block()

      2
      |> insert_list(:transaction, from_address: address)
      |> with_block(first_block)

      found_transactions = Etherscan.list_transactions(address.hash)

      block_numbers_order = Enum.map(found_transactions, & &1.block_number)

      assert block_numbers_order == Enum.sort(block_numbers_order)
    end

    test "orders transactions by block, in descending order" do
      first_block = insert(:block)
      second_block = insert(:block)
      address = insert(:address)

      2
      |> insert_list(:transaction, from_address: address)
      |> with_block(second_block)

      2
      |> insert_list(:transaction, from_address: address)
      |> with_block()

      2
      |> insert_list(:transaction, from_address: address)
      |> with_block(first_block)

      options = %{order_by_direction: :desc}

      found_transactions = Etherscan.list_transactions(address.hash, options)

      block_numbers_order = Enum.map(found_transactions, & &1.block_number)

      assert block_numbers_order == Enum.sort(block_numbers_order, &(&1 >= &2))
    end

    test "with page_size and page_number options" do
      first_block = insert(:block)
      second_block = insert(:block)
      third_block = insert(:block)
      address = insert(:address)

      second_block_transactions =
        2
        |> insert_list(:transaction, from_address: address)
        |> with_block(second_block)

      third_block_transactions =
        2
        |> insert_list(:transaction, from_address: address)
        |> with_block(third_block)

      first_block_transactions =
        2
        |> insert_list(:transaction, from_address: address)
        |> with_block(first_block)

      options = %{page_number: 1, page_size: 2}

      page1_transactions = Etherscan.list_transactions(address.hash, options)

      page1_hashes = Enum.map(page1_transactions, & &1.hash)

      assert length(page1_transactions) == 2

      for transaction <- first_block_transactions do
        assert transaction.hash in page1_hashes
      end

      options = %{page_number: 2, page_size: 2}

      page2_transactions = Etherscan.list_transactions(address.hash, options)

      page2_hashes = Enum.map(page2_transactions, & &1.hash)

      assert length(page2_transactions) == 2

      for transaction <- second_block_transactions do
        assert transaction.hash in page2_hashes
      end

      options = %{page_number: 3, page_size: 2}

      page3_transactions = Etherscan.list_transactions(address.hash, options)

      page3_hashes = Enum.map(page3_transactions, & &1.hash)

      assert length(page3_transactions) == 2

      for transaction <- third_block_transactions do
        assert transaction.hash in page3_hashes
      end

      options = %{page_number: 4, page_size: 2}

      assert Etherscan.list_transactions(address.hash, options) == []
    end

    test "with start and end block options" do
      blocks = [_, second_block, third_block, _] = insert_list(4, :block)
      address = insert(:address)

      for block <- blocks do
        2
        |> insert_list(:transaction, from_address: address)
        |> with_block(block)
      end

      options = %{
        start_block: second_block.number,
        end_block: third_block.number
      }

      found_transactions = Etherscan.list_transactions(address.hash, options)

      expected_block_numbers = [second_block.number, third_block.number]

      assert length(found_transactions) == 4

      for transaction <- found_transactions do
        assert transaction.block_number in expected_block_numbers
      end
    end

    test "with start_block but no end_block option" do
      blocks = [_, _, third_block, fourth_block] = insert_list(4, :block)
      address = insert(:address)

      for block <- blocks do
        2
        |> insert_list(:transaction, from_address: address)
        |> with_block(block)
      end

      options = %{
        start_block: third_block.number
      }

      found_transactions = Etherscan.list_transactions(address.hash, options)

      expected_block_numbers = [third_block.number, fourth_block.number]

      assert length(found_transactions) == 4

      for transaction <- found_transactions do
        assert transaction.block_number in expected_block_numbers
      end
    end

    test "with end_block but no start_block option" do
      blocks = [first_block, second_block, _, _] = insert_list(4, :block)
      address = insert(:address)

      for block <- blocks do
        2
        |> insert_list(:transaction, from_address: address)
        |> with_block(block)
      end

      options = %{
        end_block: second_block.number
      }

      found_transactions = Etherscan.list_transactions(address.hash, options)

      expected_block_numbers = [first_block.number, second_block.number]

      assert length(found_transactions) == 4

      for transaction <- found_transactions do
        assert transaction.block_number in expected_block_numbers
      end
    end

    test "with filter_by: 'to' option with one matching transaction" do
      address = insert(:address)
      contract_address = insert(:contract_address)

      :transaction
      |> insert(to_address: address)
      |> with_block()

      :transaction
      |> insert(from_address: address, to_address: nil)
      |> with_contract_creation(contract_address)
      |> with_block()

      options = %{filter_by: "to"}

      found_transactions = Etherscan.list_transactions(address.hash, options)

      assert length(found_transactions) == 1
    end

    test "with filter_by: 'to' option with non-matching transaction" do
      address = insert(:address)
      contract_address = insert(:contract_address)

      :transaction
      |> insert(from_address: address, to_address: nil)
      |> with_contract_creation(contract_address)
      |> with_block()

      options = %{filter_by: "to"}

      found_transactions = Etherscan.list_transactions(address.hash, options)

      assert length(found_transactions) == 0
    end

    test "with filter_by: 'from' option with one matching transaction" do
      address = insert(:address)

      :transaction
      |> insert(to_address: address)
      |> with_block()

      :transaction
      |> insert(from_address: address)
      |> with_block()

      options = %{filter_by: "from"}

      found_transactions = Etherscan.list_transactions(address.hash, options)

      assert length(found_transactions) == 1
    end

    test "with filter_by: 'from' option with non-matching transaction" do
      address = insert(:address)
      other_address = insert(:address)

      :transaction
      |> insert(from_address: other_address, to_address: nil)
      |> with_block()

      options = %{filter_by: "from"}

      found_transactions = Etherscan.list_transactions(address.hash, options)

      assert length(found_transactions) == 0
    end
  end

  describe "list_internal_transactions/1" do
    test "with empty db" do
      transaction = build(:transaction)

      assert Etherscan.list_internal_transactions(transaction.hash) == []
    end

    test "response includes all the expected fields" do
      address = insert(:address)
      contract_address = insert(:contract_address)

      block = insert(:block)

      transaction =
        :transaction
        |> insert(from_address: address, to_address: nil)
        |> with_contract_creation(contract_address)
        |> with_block(block)

      internal_transaction =
        :internal_transaction_create
        |> insert(transaction: transaction, index: 0, from_address: address)
        |> with_contract_creation(contract_address)

      [found_internal_transaction] = Etherscan.list_internal_transactions(transaction.hash)

      assert found_internal_transaction.block_number == block.number
      assert found_internal_transaction.block_timestamp == block.timestamp
      assert found_internal_transaction.from_address_hash == internal_transaction.from_address_hash
      assert found_internal_transaction.to_address_hash == internal_transaction.to_address_hash
      assert found_internal_transaction.value == internal_transaction.value

      assert found_internal_transaction.created_contract_address_hash ==
               internal_transaction.created_contract_address_hash

      assert found_internal_transaction.input == internal_transaction.input
      assert found_internal_transaction.type == internal_transaction.type
      assert found_internal_transaction.gas == internal_transaction.gas
      assert found_internal_transaction.gas_used == internal_transaction.gas_used
      assert found_internal_transaction.error == internal_transaction.error
    end

    test "with transaction with 0 internal transactions" do
      transaction =
        :transaction
        |> insert()
        |> with_block()

      assert Etherscan.list_internal_transactions(transaction.hash) == []
    end

    test "with transaction with multiple internal transactions" do
      transaction =
        :transaction
        |> insert()
        |> with_block()

      for index <- 0..2 do
        insert(:internal_transaction, transaction: transaction, index: index)
      end

      found_internal_transactions = Etherscan.list_internal_transactions(transaction.hash)

      assert length(found_internal_transactions) == 3
    end

    test "only returns internal transactions that belong to the transaction" do
      transaction1 =
        :transaction
        |> insert()
        |> with_block()

      transaction2 =
        :transaction
        |> insert()
        |> with_block()

      insert(:internal_transaction, transaction: transaction1, index: 0)
      insert(:internal_transaction, transaction: transaction1, index: 1)
      insert(:internal_transaction, transaction: transaction2, index: 0, type: :reward)

      internal_transactions1 = Etherscan.list_internal_transactions(transaction1.hash)

      assert length(internal_transactions1) == 2

      internal_transactions2 = Etherscan.list_internal_transactions(transaction2.hash)

      assert length(internal_transactions2) == 1
    end

    # Note that `list_internal_transactions/1` relies on
    # `Chain.where_transaction_has_multiple_transactions/1` to ensure the
    # following behavior:
    #
    # * exclude internal transactions of type call with no siblings in the
    #   transaction
    #
    # * include internal transactions of type create, reward, or suicide
    #   even when they are alone in the parent transaction
    #
    # These two requirements are tested in `Explorer.ChainTest`.
  end

  describe "list_token_transfers/2" do
    test "with empty db" do
      address = build(:address)

      assert Etherscan.list_token_transfers(address.hash, nil) == []
    end

    test "with from address" do
      transaction =
        :transaction
        |> insert()
        |> with_block()

      token_transfer = insert(:token_transfer, transaction: transaction)

      [found_token_transfer] = Etherscan.list_token_transfers(token_transfer.from_address_hash, nil)

      assert token_transfer.from_address_hash == found_token_transfer.from_address_hash
    end

    test "with to address" do
      transaction =
        :transaction
        |> insert()
        |> with_block()

      token_transfer = insert(:token_transfer, transaction: transaction)

      [found_token_transfer] = Etherscan.list_token_transfers(token_transfer.to_address_hash, nil)

      assert token_transfer.to_address_hash == found_token_transfer.to_address_hash
    end

    test "with address with 0 token transfers" do
      address = insert(:address)

      assert Etherscan.list_token_transfers(address.hash, nil) == []
    end

    test "with address with multiple token transfers" do
      address1 = insert(:address)
      address2 = insert(:address)

      transaction =
        :transaction
        |> insert()
        |> with_block()

      insert(:token_transfer, from_address: address1, transaction: transaction)
      insert(:token_transfer, from_address: address1, transaction: transaction)
      insert(:token_transfer, from_address: address2, transaction: transaction)

      found_token_transfers = Etherscan.list_token_transfers(address1.hash, nil)

      assert length(found_token_transfers) == 2

      for found_token_transfer <- found_token_transfers do
        assert found_token_transfer.from_address_hash == address1.hash
      end
    end

    test "confirmations value is calculated correctly" do
      insert(:block)

      transaction =
        :transaction
        |> insert()
        |> with_block()

      token_transfer = insert(:token_transfer, transaction: transaction)

      insert(:block)

      [found_token_transfer] = Etherscan.list_token_transfers(token_transfer.from_address_hash, nil)

      {:ok, max_block_number} = Chain.max_block_number()
      expected_confirmations = max_block_number - transaction.block_number

      assert found_token_transfer.confirmations == expected_confirmations
    end

    test "returns all required fields" do
      transaction =
        %{block: block} =
        :transaction
        |> insert()
        |> with_block()

      token_transfer = insert(:token_transfer, transaction: transaction)

      {:ok, token} = Chain.token_from_address_hash(token_transfer.token_contract_address_hash)

      [found_token_transfer] = Etherscan.list_token_transfers(token_transfer.from_address_hash, nil)

      assert found_token_transfer.block_number == transaction.block_number
      assert found_token_transfer.block_timestamp == block.timestamp
      assert found_token_transfer.transaction_hash == token_transfer.transaction_hash
      assert found_token_transfer.transaction_nonce == transaction.nonce
      assert found_token_transfer.block_hash == block.hash
      assert found_token_transfer.from_address_hash == token_transfer.from_address_hash
      assert found_token_transfer.token_contract_address_hash == token_transfer.token_contract_address_hash
      assert found_token_transfer.to_address_hash == token_transfer.to_address_hash
      assert found_token_transfer.amount == token_transfer.amount
      assert found_token_transfer.token_name == token.name
      assert found_token_transfer.token_symbol == token.symbol
      assert found_token_transfer.token_decimals == token.decimals
      assert found_token_transfer.transaction_index == transaction.index
      assert found_token_transfer.transaction_gas == transaction.gas
      assert found_token_transfer.transaction_gas_price == transaction.gas_price
      assert found_token_transfer.transaction_gas_used == transaction.gas_used
      assert found_token_transfer.transaction_cumulative_gas_used == transaction.cumulative_gas_used
      assert found_token_transfer.transaction_input == transaction.input
      # There is a separate test to ensure confirmations are calculated correctly.
      assert found_token_transfer.confirmations
    end

    test "orders token transfers by block, in ascending order (default)" do
      address = insert(:address)

      first_block = insert(:block)
      second_block = insert(:block)

      transaction1 =
        :transaction
        |> insert()
        |> with_block(second_block)

      transaction2 =
        :transaction
        |> insert()
        |> with_block()

      transaction3 =
        :transaction
        |> insert()
        |> with_block(first_block)

      insert(:token_transfer, from_address: address, transaction: transaction2)
      insert(:token_transfer, from_address: address, transaction: transaction1)
      insert(:token_transfer, from_address: address, transaction: transaction3)

      found_token_transfers = Etherscan.list_token_transfers(address.hash, nil)

      block_numbers_order = Enum.map(found_token_transfers, & &1.block_number)

      assert block_numbers_order == Enum.sort(block_numbers_order)
    end

    test "orders token transfers by block, in descending order" do
      address = insert(:address)

      first_block = insert(:block)
      second_block = insert(:block)

      transaction1 =
        :transaction
        |> insert()
        |> with_block(second_block)

      transaction2 =
        :transaction
        |> insert()
        |> with_block()

      transaction3 =
        :transaction
        |> insert()
        |> with_block(first_block)

      insert(:token_transfer, from_address: address, transaction: transaction2)
      insert(:token_transfer, from_address: address, transaction: transaction1)
      insert(:token_transfer, from_address: address, transaction: transaction3)

      options = %{order_by_direction: :desc}

      found_token_transfers = Etherscan.list_token_transfers(address.hash, nil, options)

      block_numbers_order = Enum.map(found_token_transfers, & &1.block_number)

      assert block_numbers_order == Enum.sort(block_numbers_order, &(&1 >= &2))
    end

    test "with page_size and page_number options" do
      address = insert(:address)

      first_block = insert(:block)
      second_block = insert(:block)
      third_block = insert(:block)

      transaction1 =
        :transaction
        |> insert()
        |> with_block(first_block)

      transaction2 =
        :transaction
        |> insert()
        |> with_block(second_block)

      transaction3 =
        :transaction
        |> insert()
        |> with_block(third_block)

      second_block_token_transfers = insert_list(2, :token_transfer, from_address: address, transaction: transaction2)

      third_block_token_transfers = insert_list(2, :token_transfer, from_address: address, transaction: transaction3)

      first_block_token_transfers = insert_list(2, :token_transfer, from_address: address, transaction: transaction1)

      options1 = %{page_number: 1, page_size: 2}

      page1_token_transfers = Etherscan.list_token_transfers(address.hash, nil, options1)

      page1_hashes = Enum.map(page1_token_transfers, & &1.transaction_hash)

      assert length(page1_token_transfers) == 2

      for token_transfer <- first_block_token_transfers do
        assert token_transfer.transaction_hash in page1_hashes
      end

      options2 = %{page_number: 2, page_size: 2}

      page2_token_transfers = Etherscan.list_token_transfers(address.hash, nil, options2)

      page2_hashes = Enum.map(page2_token_transfers, & &1.transaction_hash)

      assert length(page2_token_transfers) == 2

      for token_transfer <- second_block_token_transfers do
        assert token_transfer.transaction_hash in page2_hashes
      end

      options3 = %{page_number: 3, page_size: 2}

      page3_token_transfers = Etherscan.list_token_transfers(address.hash, nil, options3)

      page3_hashes = Enum.map(page3_token_transfers, & &1.transaction_hash)

      assert length(page3_token_transfers) == 2

      for token_transfer <- third_block_token_transfers do
        assert token_transfer.transaction_hash in page3_hashes
      end

      options4 = %{page_number: 4, page_size: 2}

      assert Etherscan.list_token_transfers(address.hash, nil, options4) == []
    end

    test "with start and end block options" do
      blocks = [_, second_block, third_block, _] = insert_list(4, :block)
      address = insert(:address)

      for block <- blocks do
        transaction =
          :transaction
          |> insert()
          |> with_block(block)

        insert(:token_transfer, from_address: address, transaction: transaction)
      end

      options = %{
        start_block: second_block.number,
        end_block: third_block.number
      }

      found_token_transfers = Etherscan.list_token_transfers(address.hash, nil, options)

      expected_block_numbers = [second_block.number, third_block.number]

      assert length(found_token_transfers) == 2

      for token_transfer <- found_token_transfers do
        assert token_transfer.block_number in expected_block_numbers
      end
    end

    test "with start_block but no end_block option" do
      blocks = [_, _, third_block, fourth_block] = insert_list(4, :block)
      address = insert(:address)

      for block <- blocks do
        transaction =
          :transaction
          |> insert()
          |> with_block(block)

        insert(:token_transfer, from_address: address, transaction: transaction)
      end

      options = %{start_block: third_block.number}

      found_token_transfers = Etherscan.list_token_transfers(address.hash, nil, options)

      expected_block_numbers = [third_block.number, fourth_block.number]

      assert length(found_token_transfers) == 2

      for token_transfer <- found_token_transfers do
        assert token_transfer.block_number in expected_block_numbers
      end
    end

    test "with end_block but no start_block option" do
      blocks = [first_block, second_block, _, _] = insert_list(4, :block)
      address = insert(:address)

      for block <- blocks do
        transaction =
          :transaction
          |> insert()
          |> with_block(block)

        insert(:token_transfer, from_address: address, transaction: transaction)
      end

      options = %{end_block: second_block.number}

      found_token_transfers = Etherscan.list_token_transfers(address.hash, nil, options)

      expected_block_numbers = [first_block.number, second_block.number]

      assert length(found_token_transfers) == 2

      for token_transfer <- found_token_transfers do
        assert token_transfer.block_number in expected_block_numbers
      end
    end

    test "with contract_address option" do
      address = insert(:address)

      contract_address = insert(:contract_address)

      insert(:token, contract_address: contract_address)

      transaction =
        :transaction
        |> insert()
        |> with_block()

      insert(:token_transfer, from_address: address, transaction: transaction)
      insert(:token_transfer, from_address: address, token_contract_address: contract_address, transaction: transaction)

      [found_token_transfer] = Etherscan.list_token_transfers(address.hash, contract_address.hash)

      assert found_token_transfer.token_contract_address_hash == contract_address.hash
    end
  end

  describe "list_blocks/1" do
    test "it returns all required fields" do
      %{block_range: range} = block_reward = insert(:block_reward)

      block = insert(:block, number: Enum.random(Range.new(range.from, range.to)))

      # irrelevant transaction
      insert(:transaction)

      :transaction
      |> insert(gas_price: 1)
      |> with_block(block, gas_used: 1)

      expected_reward =
        block_reward.reward
        |> Wei.to(:wei)
        |> Decimal.add(Decimal.new(1))
        |> Wei.from(:wei)

      expected = [
        %{
          number: block.number,
          timestamp: block.timestamp,
          reward: expected_reward
        }
      ]

      assert Etherscan.list_blocks(block.miner_hash) == expected
    end

    test "with block containing multiple transactions" do
      %{block_range: range} = block_reward = insert(:block_reward)

      block = insert(:block, number: Enum.random(Range.new(range.from, range.to)))

      # irrelevant transaction
      insert(:transaction)

      :transaction
      |> insert(gas_price: 1)
      |> with_block(block, gas_used: 1)

      :transaction
      |> insert(gas_price: 1)
      |> with_block(block, gas_used: 2)

      expected_reward =
        block_reward.reward
        |> Wei.to(:wei)
        |> Decimal.add(Decimal.new(3))
        |> Wei.from(:wei)

      expected = [
        %{
          number: block.number,
          timestamp: block.timestamp,
          reward: expected_reward
        }
      ]

      assert Etherscan.list_blocks(block.miner_hash) == expected
    end

    test "with block without transactions" do
      %{block_range: range} = block_reward = insert(:block_reward)

      block = insert(:block, number: Enum.random(Range.new(range.from, range.to)))

      # irrelevant transaction
      insert(:transaction)

      expected = [
        %{
          number: block.number,
          timestamp: block.timestamp,
          reward: block_reward.reward
        }
      ]

      assert Etherscan.list_blocks(block.miner_hash) == expected
    end

    test "with multiple blocks" do
      %{block_range: range} = block_reward = insert(:block_reward)

      block_numbers = Range.new(range.from, range.to)

      [block_number1, block_number2] = Enum.take(block_numbers, 2)

      address = insert(:address)

      block1 = insert(:block, number: block_number1, miner: address)
      block2 = insert(:block, number: block_number2, miner: address)

      # irrelevant transaction
      insert(:transaction)

      :transaction
      |> insert(gas_price: 2)
      |> with_block(block1, gas_used: 2)

      :transaction
      |> insert(gas_price: 2)
      |> with_block(block1, gas_used: 2)

      :transaction
      |> insert(gas_price: 3)
      |> with_block(block2, gas_used: 3)

      :transaction
      |> insert(gas_price: 3)
      |> with_block(block2, gas_used: 3)

      expected_reward_block1 =
        block_reward.reward
        |> Wei.to(:wei)
        |> Decimal.add(Decimal.new(8))
        |> Wei.from(:wei)

      expected_reward_block2 =
        block_reward.reward
        |> Wei.to(:wei)
        |> Decimal.add(Decimal.new(18))
        |> Wei.from(:wei)

      expected = [
        %{
          number: block2.number,
          timestamp: block2.timestamp,
          reward: expected_reward_block2
        },
        %{
          number: block1.number,
          timestamp: block1.timestamp,
          reward: expected_reward_block1
        }
      ]

      assert Etherscan.list_blocks(address.hash) == expected
    end

    test "with pagination options" do
      %{block_range: range} = block_reward = insert(:block_reward)

      block_numbers = Range.new(range.from, range.to)

      [block_number1, block_number2] = Enum.take(block_numbers, 2)

      address = insert(:address)

      block1 = insert(:block, number: block_number1, miner: address)
      block2 = insert(:block, number: block_number2, miner: address)

      :transaction
      |> insert(gas_price: 2)
      |> with_block(block1, gas_used: 2)

      expected_reward =
        block_reward.reward
        |> Wei.to(:wei)
        |> Decimal.add(Decimal.new(4))
        |> Wei.from(:wei)

      expected1 = [
        %{
          number: block2.number,
          timestamp: block2.timestamp,
          reward: block_reward.reward
        }
      ]

      expected2 = [
        %{
          number: block1.number,
          timestamp: block1.timestamp,
          reward: expected_reward
        }
      ]

      options1 = %{page_number: 1, page_size: 1}
      options2 = %{page_number: 2, page_size: 1}
      options3 = %{page_number: 3, page_size: 1}

      assert Etherscan.list_blocks(address.hash, options1) == expected1
      assert Etherscan.list_blocks(address.hash, options2) == expected2
      assert Etherscan.list_blocks(address.hash, options3) == []
    end
  end

  describe "get_token_balance/2" do
    test "with a single matching token_balance record" do
      token_balance =
        %{token_contract_address_hash: contract_address_hash, address_hash: address_hash} = insert(:token_balance)

      found_token_balance = Etherscan.get_token_balance(contract_address_hash, address_hash)

      assert found_token_balance.id == token_balance.id
    end

    test "returns token balance in latest block" do
      token = insert(:token)

      contract_address_hash = token.contract_address_hash

      address = insert(:address)

      token_details1 = %{
        token_contract_address_hash: contract_address_hash,
        address: address,
        block_number: 5
      }

      token_details2 = %{
        token_contract_address_hash: contract_address_hash,
        address: address,
        block_number: 15
      }

      token_details3 = %{
        token_contract_address_hash: contract_address_hash,
        address: address,
        block_number: 10
      }

      _token_balance1 = insert(:token_balance, token_details1)
      token_balance2 = insert(:token_balance, token_details2)
      _token_balance3 = insert(:token_balance, token_details3)

      found_token_balance = Etherscan.get_token_balance(contract_address_hash, address.hash)

      assert found_token_balance.id == token_balance2.id
    end
  end

  describe "get_transaction_error/1" do
    test "with a transaction that doesn't exist" do
      transaction = build(:transaction)

      refute Etherscan.get_transaction_error(transaction.hash)
    end

    test "with a transaction with no errors" do
      transaction = insert(:transaction)

      refute Etherscan.get_transaction_error(transaction.hash)
    end

    test "with a transaction with an error" do
      transaction =
        :transaction
        |> insert()
        |> with_block(status: :error)

      internal_transaction_details = [
        transaction: transaction,
        index: 0,
        type: :reward,
        error: "some error"
      ]

      insert(:internal_transaction, internal_transaction_details)

      assert Etherscan.get_transaction_error(transaction.hash) == "some error"
    end
  end
end
