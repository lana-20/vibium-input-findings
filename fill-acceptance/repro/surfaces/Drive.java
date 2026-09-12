import com.vibium.*;
public class Drive {
  record C(String id, String html, String sel, String val) {}
  public static void main(String[] a) {
    C[] cases = {
      new C("number-abc",  "<input id=n type=number value=\"\">", "#n", "abc"),
      new C("date-bad",    "<input id=d type=date value=\"\">",   "#d", "not-a-date"),
      new C("number-42",   "<input id=n type=number value=\"\">", "#n", "42"),
    };
    Browser b = Vibium.start();
    try {
      Page p = b.newPage();
      for (C c : cases) {
        p.go("data:text/html," + c.html());
        String err = "";
        try { p.find(c.sel()).fill(c.val()); }
        catch (Exception e) { err = e.getClass().getSimpleName() + ": " + String.valueOf(e.getMessage()).split("\n")[0]; }
        String v = "";
        try { v = p.find(c.sel()).value(); } catch (Exception e) { v = "<value failed>"; }
        System.out.println("java|" + c.id() + "|" + v + "|" + err);
      }
    } finally { b.stop(); }
  }
}
