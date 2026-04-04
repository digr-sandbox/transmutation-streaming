import 'package:transmutation/api.dart';

class UiController extends BaseController {
    final String title;
    UiController({required this.title});

    @override
    void onInit() {
        print('Dart initialized: $title');
        super.onInit();
    }
}