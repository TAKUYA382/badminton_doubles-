import { Application } from "@hotwired/stimulus"
const application = Application.start()

import MatchEditorController from "./match_editor_controller"
application.register("match-editor", MatchEditorController)
