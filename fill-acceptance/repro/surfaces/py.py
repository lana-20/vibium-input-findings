from vibium.sync_api import browser
cases = [("number-abc", '<input id=n type=number value="">', "#n", "abc"),
         ("date-bad",   '<input id=d type=date value="">',   "#d", "not-a-date"),
         ("number-42",  '<input id=n type=number value="">', "#n", "42")]
b = browser.start()
try:
    p = b.new_page()
    for cid, html, sel, val in cases:
        p.go("data:text/html," + html)
        err = ""
        try: p.find(sel).fill(val)
        except Exception as e: err = "%s: %s" % (type(e).__name__, str(e).split("\n")[0])
        try: v = p.find(sel).value()
        except Exception: v = "<value failed>"
        print("python|%s|%s|%s" % (cid, v, err))
finally:
    b.stop()
