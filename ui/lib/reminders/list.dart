import 'package:flutter/material.dart';
import 'dart:io';

import 'package:ui/app/navigation.dart';
import 'package:ui/reminders/requests.dart';
import 'package:ui/reminders/edit.dart';

typedef ReminderCallback = Function(Map<String, dynamic>);
enum _reminderState { normal, deleting, editing }

const String _fieldReminderState = 'state';
const String _fieldUpdatedAt = 'updatedAt';

class _ReminderList extends InheritedWidget {
  final List<Map<String, dynamic>> reminders;

  _ReminderList({Key key, @required this.reminders, @required Widget child})
      : super(key: key, child: child);

  static _ReminderList of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ReminderList>();
  }

  @override
  bool updateShouldNotify(_ReminderList old) => reminders != old.reminders;
}

class _DismissableReminder extends StatefulWidget {
  final Map<String, dynamic> _reminder;
  ReminderCallback _remove;
  ReminderCallback _update;

  _DismissableReminder(this._reminder,
      {ReminderCallback remove, ReminderCallback update, Key key})
      : super(key: key) {
    _remove = (_remove == null) ? remove : null;
    _update = (_update == null) ? update : null;
  }

  void remove() {
    if (_remove != null) _remove(_reminder);
  }

  void update() {
    if (_update != null) _update(_reminder);
  }

  @override
  _DismissableReminderState createState() => _DismissableReminderState();
}

class _DismissableReminderState extends State<_DismissableReminder> {
  _reminderState _state = _reminderState.normal;

  @override
  void initState() {
    super.initState();
    if (widget._reminder.containsKey(_fieldReminderState)) {
      _state = widget._reminder[_fieldReminderState];
    }
  }

  Future<TupleReminder> _removeFromServer() async {
    TupleReminder t = await deleteReminder(widget._reminder[fieldGuid]);

    // If deleted, or does not exist (already deleted), remove this reminder completely
    if (t.httpStatus == HttpStatus.ok || t.httpStatus == HttpStatus.notFound) {
      widget.remove();
    }

    return t;
  }

  _setState(_reminderState state) {
    _state = widget._reminder[_fieldReminderState] = state;
  }

  void _delete() {
    setState(() {
      _setState(_reminderState.deleting);
    });
  }

  void _undelete() {
    _setState(_reminderState.normal);
  }

  void _edit() {
    setState(() {
      _setState(_reminderState.editing);
    });
    globalNavigator
        .push(ReminderEditor(reminder: widget._reminder))
        .then((data) {
      if (data == null) {
        print('edit returned null ReminderTuple');
      } else {
        data.reminder.forEach((key, value) {
          print('$key: $value');
          widget._reminder[key] = value;
        });
      }
      setState(() {
        _setState(_reminderState.normal);
        widget.update();
      });
    }).catchError((error) {
      String msg = 'Error editing reminder: ${error.toString()}';
      print(msg);
      globalNavigator
          .showSnackBar('Error editing reminder: ${error.toString()}');
    });
  }

  Widget _buildDeletingReminder(
      BuildContext ctx, AsyncSnapshot<TupleReminder> snapshot) {
    Widget w;

    switch (snapshot.connectionState) {
      case ConnectionState.none:
      case ConnectionState.waiting:
      case ConnectionState.active:
        w = Center(
            child: Icon(Icons.remove_circle, color: Colors.red, size: 30.0));
        break;
      case ConnectionState.done:
        TupleReminder t = snapshot.data;
        String msg;

        if (snapshot.hasError) {
          // undelete because the delete request failed somehow
          _undelete();
          msg = snapshot.error.toString();
        } else if (t.httpStatus != HttpStatus.ok) {
          Scaffold.of(ctx).showSnackBar(
              SnackBar(content: Text('Delete failed: ${snapshot.error}')));
          msg = t.reminder[fieldMessage];
        } else {
          Scaffold.of(ctx).showSnackBar(
              SnackBar(content: Text('Deleted: ${t.reminder[fieldGuid]}')));
        }

        w = msg == null
            ? Center(
                child: Icon(Icons.remove_circle, color: Colors.red, size: 30.0))
            : Center(
                child: Row(children: <Widget>[
                Icon(Icons.sync_problem, color: Colors.red, size: 30.0),
                Expanded(child: Text(msg, style: TextStyle(color: Colors.red)))
              ]));

        break;
    }

    return w;
  }

  @override
  Widget build(BuildContext ctx) {
    if (_state == _reminderState.deleting) {
      return FutureBuilder(
          future: _removeFromServer(), builder: _buildDeletingReminder);
    } else if (_state == _reminderState.editing) {
      return Container(
          color: Colors.blue,
          child: Icon(Icons.edit, color: Colors.white, size: 30.0));
    } else {
      String uuid = widget._reminder[fieldGuid];
      return Dismissible(
          key: Key(uuid),
          onDismissed: (direction) {
            if (direction == DismissDirection.endToStart)
              _delete();
            else if (direction == DismissDirection.startToEnd) {
              _edit();
            }
          },
          background: Container(
              color: Colors.blue,
              child: Icon(Icons.edit, color: Colors.white, size: 30.0)),
          secondaryBackground: Container(
              color: Colors.red,
              child: Icon(Icons.delete, color: Colors.white, size: 30.0)),
          child: ListTile(title: Text(widget._reminder[fieldMessage])));
    }
  }
}

class ReminderQuery extends StatefulWidget {
  ReminderQuery({Key key}) : super(key: key);

  @override
  ReminderQueryState createState() => ReminderQueryState();
}

class ReminderQueryState extends State<ReminderQuery> {
  Future<List<Map<String, dynamic>>> _futureReminders;
  List<Map<String, dynamic>> _reminders;

  Future<List<Map<String, dynamic>>> _getReminders() async => getAllReminders();

  @override
  void initState() {
    super.initState();
    _futureReminders = _getReminders();
  }

  /// Handler for the refresh action -- causes a fresh build.
  Future<Null> onRefresh() async {
    setState(() {
      _futureReminders = _getReminders();
    });
  }

  /// Removes a [reminder] and calls [setState].
  ///
  /// This is necessary because multiple deletes can occur concurrently.
  /// [FutureBuilder] wraps the go-reminders delete, therefore List indexing
  /// could change during the remote delete.
  void _removeReminder(Map<String, dynamic> reminder) {
    for (int i = 0; i < _reminders.length; i++) {
      if (reminder[fieldGuid] == _reminders[i][fieldGuid]) {
        setState(() {
          _reminders.removeAt(i);
        });
        break;
      }
    }
  }

  /// Updates a [reminder] and calls [setState].
  ///
  /// This is necessary because multiple deletes can occur concurrently.
  /// [FutureBuilder] wraps the go-reminders delete, therefore List indexing
  /// could change during the remote delete.
  void _updateReminder(reminder) {
    print('ReminderQueryState: setState and reset _futureReminders.');
    setState(() {
      _futureReminders = _getReminders();
    });
  }

  /// Implements the [FutureBuilder] builder.
  Widget _buildQueryResults(
      BuildContext ctx, AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
    Widget w;

    switch (snapshot.connectionState) {
      case ConnectionState.done:
        if (snapshot.hasError) {
          w = Center(
              child: Column(children: <Widget>[
            Expanded(
                child:
                    Icon(Icons.error_outline, color: Colors.red, size: 30.0)),
            Text(snapshot.error.toString())
          ]));
        } else {
          _reminders = snapshot.data;
          _reminders
              .sort((a, b) => a[_fieldUpdatedAt].compareTo(b[_fieldUpdatedAt]));
          w = _ReminderList(
              reminders: _reminders,
              child: RefreshIndicator(
                  child: ListView.builder(
                      padding: const EdgeInsets.all(8.0),
                      itemCount: _reminders.length,
                      itemBuilder: (BuildContext ctx, int index) {
                        return _DismissableReminder(_reminders[index],
                            remove: _removeReminder,
                            update: _updateReminder,
                            key: Key(_reminders[index][fieldGuid]));
                      }),
                  onRefresh: onRefresh));
        }
        break;
      default:
        w = Center(child: CircularProgressIndicator());
        break;
    }

    return w;
  }

  /// Builds the view widget for this reminder.
  @override
  Widget build(BuildContext ctx) {
    return Container(
        padding: EdgeInsets.all(10.0),
        child: FutureBuilder(
            future: _futureReminders, builder: _buildQueryResults));
  }
}
