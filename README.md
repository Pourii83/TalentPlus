# TalentPlus

An addon for **OctoWoW** (1.12.1 / Vanilla client) that stops talents being learned by accident.
Clicking a talent only *plans* it. Nothing is learned until you press **Learn** and confirm.

ادانی برای OctoWoW که جلوی لرن شدن اشتباهی تلنت‌ها را می‌گیرد. با کلیک روی تلنت فقط «برنامه‌ریزی» می‌شود
و تا وقتی دکمه **Learn** را نزنید و تأیید نکنید، هیچ پوینتی خرج نمی‌شود.

## Usage / نحوه استفاده

| Action | Result |
| --- | --- |
| Left-click a talent | Plan one rank (shown in blue) |
| Shift + left-click | Plan every rank you can |
| Right-click a planned talent | Remove one planned rank |
| Shift + right-click | Remove all planned ranks of that talent |
| **Learn (N)** button | Shows a summary and asks you to confirm, then learns everything |
| **Clear** button | Throws away the plan |

- The plan checks the same rules as the server: free points, 5 points per tier, and maxed prerequisites.
- You can't remove a planned talent that another planned talent depends on.
- Ranks are sent one at a time, in the order you planned them. If the server rejects one, learning stops and the rest of your plan is kept.

## Slash commands

- `/tplus learn`: learn the planned talents
- `/tplus clear`: clear the plan
- `/tplus confirm`: turn the confirmation popup on or off (on by default)

## Installation / نصب

1. Download the repository (Code → Download ZIP) and extract it.
2. Rename the folder to exactly `TalentPlus` (GitHub names it `TalentPlus-main`).
3. Put it in `World of Warcraft/Interface/AddOns/TalentPlus/`, so that `TalentPlus.toc` is directly inside that folder.
4. Restart the game and enable **TalentPlus** on the AddOns screen.

۱. فایل ZIP را دانلود و اکسترکت کنید.
۲. اسم پوشه را دقیقاً `TalentPlus` بگذارید (نه `TalentPlus-main`).
۳. پوشه را در `Interface/AddOns` کپی کنید، طوری که فایل `TalentPlus.toc` مستقیماً داخل پوشه `TalentPlus` باشد.
۴. بازی را ریستارت کنید و ادان را در بخش AddOns فعال کنید.
