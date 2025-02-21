# pyright: reportDeprecated=false
import json
from enum import Enum
from typing import Any, Optional, override

from flet.core.control import Control, OptionalNumber
from flet.core.control_event import ControlEvent
from flet.core.event_handler import EventHandler
from flet.core.ref import Ref
from flet.core.types import (
    PagePlatform,
    OptionalEventCallable,
    OptionalControlEventCallable,
)


class PurchaseStatus(Enum):
    PENDING = "pending"
    PURCHASED = "purchased"
    ERROR = "error"
    RESTORED = "restored"
    CANCELED = "canceled"


class ProductType(Enum):
    CONSUMABLE = "consumable"
    NON_CONSUMABLE = "non_consumable"
    SUBSCRIPTION = "subscription"


class ProductDetails:
    def __init__(self, data: dict[str, Any]):
        self.id: str = data.get("id", "")
        self.title: str = data.get("title", "")
        self.description: str = data.get("description", "")
        self.price: str = data.get("price", "")
        self.raw_price: float = data.get("rawPrice", 0.0)
        self.currency_code: str = data.get("currencyCode", "")
        self.currency_symbol: str = data.get("currencySymbol", "")
        self.type: ProductType = ProductType(data.get("type", "consumable"))


class PurchaseEvent(ControlEvent):
    def __init__(self, e: ControlEvent):
        super().__init__(e.target, e.name, e.data, e.control, e.page)
        d = json.loads(e.data)
        self.product_id: str = d.get("productId", "")
        self.status: PurchaseStatus = PurchaseStatus(d.get("status", "error"))
        self.transaction_id: str = d.get("transactionId", "")
        self.error_message: Optional[str] = d.get("errorMessage")


class InAppPurchase(Control):
    """
    A control to handle in-app purchases on iOS and Android platforms.

    This control allows you to query product details, make purchases, restore previous purchases,
    and handle subscription management within your Flet application.

    ## Examples
    ```python
    import flet as ft
    import flet_iap as fiap

    def main(page: ft.Page):
        def on_product_ready(e):
            print(f"Products ready: {len(e.products)}")
            for product in e.products:
                print(f"Product: {product.title} - {product.price}")

        def on_purchase_updated(e):
            if e.status == fiap.PurchaseStatus.PURCHASED:
                print(f"Successfully purchased: {e.product_id}")
            elif e.status == fiap.PurchaseStatus.ERROR:
                print(f"Purchase error: {e.error_message}")

        iap = fiap.InAppPurchase(
            product_ids=["premium_upgrade", "coins_package"],
            on_products_ready=on_product_ready,
            on_purchase_updated=on_purchase_updated,
        )

        page.add(iap)

        # Later when user wants to purchase
        buy_btn = ft.ElevatedButton("Buy Premium",
                                   on_click=lambda _: iap.buy_product("premium_upgrade"))
        page.add(buy_btn)

    ft.app(main)
    ```

    ## Properties

    ### `product_ids`

    List of product IDs to query from the app stores.

    ## Events

    ### `on_products_ready`

    Called when product details have been fetched from the store.

    ### `on_purchase_updated`

    Called when a purchase status has been updated.

    ### `on_purchase_error`

    Called when there is an error during the purchase process.
    """

    def __init__(
        self,
        product_ids: Optional[list[str]] = None,
        on_products_ready: OptionalControlEventCallable = None,
        on_purchase_updated: OptionalEventCallable[PurchaseEvent] = None,
        on_purchase_error: OptionalControlEventCallable = None,
        #
        # Control
        #
        ref: Optional[Ref] = None,
        visible: Optional[bool] = None,
        disabled: Optional[bool] = None,
        data: Any = None,
    ):
        Control.__init__(
            self,
            ref=ref,
            visible=visible,
            disabled=disabled,
            data=data,
        )

        self.__on_purchase_updated = EventHandler(lambda e: PurchaseEvent(e))
        self._add_event_handler(
            "purchase_updated", self.__on_purchase_updated.get_handler()
        )

        self.product_ids = product_ids
        self.on_products_ready = on_products_ready
        self.on_purchase_updated = on_purchase_updated
        self.on_purchase_error = on_purchase_error

    @override
    def _get_control_name(self):
        return "inapppurchase"

    def _check_mobile_platform(self):
        assert self.page is not None, "InAppPurchase must be added to page first."
        if self.page.platform not in [PagePlatform.ANDROID, PagePlatform.IOS]:
            raise Exception(
                "InAppPurchase is supported on Android and iOS platforms only."
            )

    def initialize(self):
        """Initialize the In-App Purchase system"""
        self._check_mobile_platform()
        self.invoke_method("initialize")

    def query_products(self, product_ids: Optional[list[str]] = None):
        """Query product details from the stores"""
        self._check_mobile_platform()
        ids = product_ids or self.product_ids
        if not ids:
            raise ValueError("No product IDs provided")
        self.invoke_method("query_products", arguments={"productIds": ids})

    def buy_product(self, product_id: str):
        """Purchase a product"""
        self._check_mobile_platform()
        self.invoke_method("buy_product", arguments={"productId": product_id})

    def restore_purchases(self):
        """Restore previous purchases"""
        self._check_mobile_platform()
        self.invoke_method("restore_purchases")

    def get_past_purchases(
        self, wait_timeout: OptionalNumber = 10
    ) -> list[dict[str, Any]]:
        """Get past purchases synchronously"""
        self._check_mobile_platform()
        result = self.invoke_method(
            "get_past_purchases", wait_for_result=True, wait_timeout=wait_timeout
        )
        return json.loads(result) if result else []

    def finish_transaction(self, transaction_id: str):
        """Complete a transaction (required on iOS)"""
        self._check_mobile_platform()
        self.invoke_method(
            "finish_transaction", arguments={"transactionId": transaction_id}
        )

    # product_ids
    @property
    def product_ids(self) -> Optional[list[str]]:
        return self._get_attr("productIds", data_type="list", def_value=[])

    @product_ids.setter
    def product_ids(self, value: Optional[list[str]]):
        self._set_attr("productIds", value)

    # on_products_ready
    @property
    def on_products_ready(self) -> OptionalControlEventCallable:
        return self._get_event_handler("products_ready")

    @on_products_ready.setter
    def on_products_ready(self, handler: OptionalControlEventCallable):
        self._add_event_handler("products_ready", handler)

    # on_purchase_updated
    @property
    def on_purchase_updated(self) -> OptionalEventCallable[PurchaseEvent]:
        return self.__on_purchase_updated.handler

    @on_purchase_updated.setter
    def on_purchase_updated(self, handler: OptionalEventCallable[PurchaseEvent]):
        self.__on_purchase_updated.handler = handler

    # on_purchase_error
    @property
    def on_purchase_error(self) -> OptionalControlEventCallable:
        return self._get_event_handler("purchase_error")

    @on_purchase_error.setter
    def on_purchase_error(self, handler: OptionalControlEventCallable):
        self._add_event_handler("purchase_error", handler)
