import WidgetKit
import SwiftUI

@main
struct FormWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NutritionWidget()
        TrainingWidget()
        TodayWidget()
        WorkoutLiveActivity()
    }
}
