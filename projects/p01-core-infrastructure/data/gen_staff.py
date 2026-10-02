"""Generate the SYNTHETIC 85-person Halden staff file (deterministic, fictional names)."""
import csv, random
r = random.Random(42)
F = "Sara Omar Lena Imran Hira Tariq Maya Zain Aisha Bilal Noor Hamza Iqra Faisal Sana Usman Mina Adil Rida Kamran Zoya Danish Alina Farhan Hania Rehan Laiba Saad Amna Waqas Eman Junaid Kiran Owais Nida Shan Mahnoor Talha Dua Yasir Anum Haris Bushra Salman Rabia Asad Fiza Arslan Komal".split()
L = "Khan Ahmed Malik Hussain Sheikh Butt Raza Qureshi Mirza Chaudhry Siddiqui Iqbal Bhatti Nawaz Javed Aslam Rauf Anwar Gill Dar Hashmi Lodhi Zafar Rana Naqvi".split()
plan = {  # dept: (count, head title, staff titles, office)
 "Management": (5, "Managing Director", ["Operations Director", "Finance Director", "Sales Director", "HR Director"], "HQ"),
 "Finance": (8, "Finance Manager", ["Accountant", "Accounts Clerk", "Payroll Officer"], "HQ"),
 "HR": (4, "HR Manager", ["HR Officer", "Recruiter"], "HQ"),
 "Sales": (20, "Sales Manager", ["Sales Executive", "Account Manager"], "HQ"),
 "Operations": (43, "Operations Manager", ["Warehouse Operative", "Forklift Driver", "Dispatcher", "Stock Controller"], "Warehouse"),
 "IT": (5, "IT Manager", ["Systems Administrator", "IT Support Officer"], "HQ"),
}
used, rows, eid = set(), [], 1000
heads = {}
for dept, (n, head, titles, office) in plan.items():
    for i in range(n):
        while True:
            f, l = r.choice(F), r.choice(L)
            if f"{f}.{l}".lower() not in used: used.add(f"{f}.{l}".lower()); break
        title = head if i == 0 else titles[(i - 1) % len(titles)]
        off = "Remote" if dept == "Sales" and i >= 8 else office  # 12 remote sales staff
        eid += 1
        if i == 0: heads[dept] = f"{f}.{l}".lower()
        mgr = "" if dept == "Management" and i == 0 else (heads["Management"] if i == 0 else heads[dept])
        rows.append([f, l, dept, title, mgr, off, eid, f"20{r.randint(15,25)}-{r.randint(1,12):02d}-{r.randint(1,28):02d}"])
with open("halden-staff.csv", "w", newline="") as fh:
    w = csv.writer(fh); w.writerow("First,Last,Department,Title,Manager,Office,EmployeeID,StartDate".split(",")); w.writerows(rows)
print(len(rows), "synthetic users written")
