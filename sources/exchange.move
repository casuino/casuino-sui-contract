// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module casuino::chipsui {
    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui_system::staking_pool::{Self, StakedSui};
    use std::vector;
    use std::option;

    struct Exchange has key {
        id: UID,
        treasury_cap: TreasuryCap<CHIPSUI>,
        liquid_pools: vector<LiquidPool>
    }

    struct LiquidPool has key, store {
        id: UID,
        owner: address,
        staked_sui: StakedSui,
        amount: u64,
        expired: u64,
    }

    struct CHIPSUI has drop {}

    const ELiquidPoolNotFound: u64 = 1;
    const ELiquidPoolNotEnoughAmount: u64 = 2;

    fun init(witness: CHIPSUI, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency<CHIPSUI>(witness, 9, b"CHIPSUI", b"CHIPSUI", b"CHIPSUI", option::none(), ctx);
        transfer::public_freeze_object(metadata);
        transfer::share_object(Exchange {
            id: object::new(ctx),
            treasury_cap: treasury_cap,
            liquid_pools:vector::empty<LiquidPool>(),
        });
    }

    public entry fun depositStakedSui(exchange: &mut Exchange, new_staked_sui: StakedSui, ctx: &mut TxContext) {
        let principal_amount = staking_pool::staked_sui_amount(&new_staked_sui);
        let sender = tx_context::sender(ctx);
        let index = index_of_ls(&exchange.liquid_pools, sender);
        if (index < vector::length(&exchange.liquid_pools)) {
            let LiquidPool { id, owner, staked_sui, amount, expired } = vector::remove(&mut exchange.liquid_pools, index);
            staking_pool::join_staked_sui(&mut staked_sui, new_staked_sui);
            let ls = LiquidPool {
                id: object::new(ctx),
                owner: sender,
                staked_sui: staked_sui,
                amount: amount + principal_amount,
                expired: 0,
            };
            vector::push_back(&mut exchange.liquid_pools, ls);
            coin::mint_and_transfer(&mut exchange.treasury_cap, principal_amount, sender, ctx);
            object::delete(id);   
        } else {
            let ls = LiquidPool {
                id: object::new(ctx),
                owner: sender,
                staked_sui: new_staked_sui,
                amount: principal_amount,
                expired: 0,
            };
            vector::push_back(&mut exchange.liquid_pools, ls);
            coin::mint_and_transfer(&mut exchange.treasury_cap, principal_amount, sender, ctx);
        }
    }

    public entry fun withdrawStakedSui(exchange: &mut Exchange, coin: Coin<CHIPSUI>, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let index = index_of_ls(&exchange.liquid_pools, sender);
        assert!(index < vector::length(&exchange.liquid_pools), ELiquidPoolNotFound);
        let LiquidPool { id, owner, staked_sui, amount, expired } = vector::remove(&mut exchange.liquid_pools, index);
        let input_amount = coin::value(&coin);
        if (amount > input_amount) {
            let withdraw_staked_sui = staking_pool::split(&mut staked_sui, input_amount, ctx);
            transfer::public_transfer(withdraw_staked_sui, owner);

            let ls = LiquidPool {
                id: object::new(ctx),
                owner: owner,
                staked_sui: staked_sui,
                amount: amount - input_amount,
                expired: 0,
            };
            vector::push_back(&mut exchange.liquid_pools, ls);
        }  else {
            transfer::public_transfer(staked_sui, owner);
        };
        
        coin::burn(&mut exchange.treasury_cap, coin);
        object::delete(id);   
    }

    fun index_of_ls(ls: &vector<LiquidPool>, sender: address): u64 {
        let i = 0;
        let l = vector::length(ls);
        while (i < l) {
            let ls = vector::borrow(ls, i);
            if (sender == ls.owner) {
                return i
            };
            i = i + 1;
       };
       return l
    }
}
