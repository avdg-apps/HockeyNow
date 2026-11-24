# HockeyNow widget (optional)

Widgets need their own Xcode target, which a source drop can't create for you. About two minutes:

1. Open the project in Xcode. File > New > Target > macOS > **Widget Extension**. Name it `HockeyNowWidget`.
   Untick "Include Live Activity" and "Include Configuration App Intent".
2. Delete the template Swift files Xcode generated, then drag `HockeyNowWidget.swift` from this folder into the new target.
3. Select the widget target > Signing & Capabilities: choose your Personal Team (a free Apple ID works for running on your own Mac).
   Add the **Outgoing Connections (Client)** capability under App Sandbox, so the widget can reach api-web.nhle.com.
4. Build and run the widget scheme, then right-click the desktop > Edit Widgets > HockeyNow.
   Right-click the widget > Edit Widget to type your team (for example EDM).

It reads the NHL's public API directly, so no App Group is needed. If your Apple ID refuses to sign the extension, the rest of
the app is unaffected: this folder is outside the app target.
