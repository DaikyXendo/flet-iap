import 'package:flet/flet.dart';
import 'in_app_purchase.dart';

CreateControlFactory createControl = (CreateControlArgs args) {
  switch (args.control.type) {
    case "in_app_purchase":
      return InAppPurchaseControl(control: args.control, backend: args.backend);
    default:
      return null;
  }
};

void ensureInitialized() {
  // nothing to do
}
